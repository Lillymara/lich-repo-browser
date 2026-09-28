import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'catalog_entry.dart';
import 'cert_check.dart';
import 'lich_ca.dart';
import 'script_header.dart';
import 'source.dart';

/// Client for the Lich repository server used by `;repository`
/// (repo.lichproject.org:7157).
///
/// Wire format, per request (one connection each):
///   client -> `key\tvalue\tkey\tvalue...\n`
///   server -> `key\tvalue\t...\n` header, then `size` bytes of body
///             (gzip when header `compression` is `gzip`).
class LichRepoSource implements RepoSource {
  LichRepoSource({
    this.host = 'repo.lichproject.org',
    this.port = 7157,
    this.clientVersion = defaultClientVersion,
    this.timeout = const Duration(seconds: 20),
  });

  /// Version string sent as `client`. Mirrors the repository.lic release this
  /// client was modeled on; the server may use it for compatibility checks.
  static const defaultClientVersion = '2.74';

  /// Certificate CNs accepted by repository.lic.
  static const _allowedCns = {'lichproject.org', 'Lich Repository'};

  final String host;
  final int port;
  final String clientVersion;
  final Duration timeout;

  @override
  String get id => 'lich';

  @override
  String get displayName => 'Lich Repository';

  @override
  Future<List<CatalogEntry>> fetchCatalog() async {
    final list = await _request({
      'action': 'list',
      'supported compressions': 'gzip',
    });
    final comments = await _request({
      'action': 'list-comments',
      'supported compressions': 'gzip',
    });
    final serverTime = int.tryParse(list.header['server time'] ?? '');
    return parseList(
      utf8.decode(list.body, allowMalformed: true),
      comments: utf8.decode(comments.body, allowMalformed: true),
      serverTime: serverTime,
    );
  }

  @override
  Future<EntryDetails> fetchDetails(CatalogEntry entry) async {
    final res = await _request({
      'action': 'inspect',
      'file': entry.name,
      'game': entry.game ?? '',
    });
    final versions = sortVersionsDesc((res.header['versions'] ?? '')
        .split(RegExp(r'[;,\s]+'))
        .where((v) => v.isNotEmpty));
    var text = utf8.decode(res.body, allowMalformed: true).trim();
    // The server usually sends an empty inspect body, so fall back to the
    // script's own header comment.
    if (text.isEmpty && entry.type == 'script') {
      text = extractScriptHeader(
          utf8.decode(await download(entry), allowMalformed: true));
    }
    return EntryDetails(text: text, versions: versions);
  }

  @override
  Future<Uint8List> download(CatalogEntry entry, {String? version}) async {
    final res = await _request({
      'action': 'download',
      'file': entry.name,
      'game': entry.game ?? '',
      'supported compressions': 'gzip',
      if (version != null) 'version': version,
    });
    if (res.header['file'] != entry.name) {
      throw RepoException('server returned ${res.header['file']} '
          'instead of ${entry.name}');
    }
    return res.body;
  }

  // ---------------------------------------------------------------------------
  // Connection

  Future<_Response> _request(Map<String, String> fields) async {
    final socket = await _connect();
    try {
      final reader = _SocketReader(socket);
      socket.write('${encodeRequest({...fields, 'client': clientVersion})}\n');
      await socket.flush();

      final header = decodeHeader(await reader.readLine().timeout(timeout));
      if (header['error'] != null) {
        throw RepoException('server says: ${header['error']}');
      }
      final size = int.tryParse(header['size'] ?? '');
      if (size == null) {
        throw RepoException('unrecognized response: $header');
      }
      var body = await reader.readBytes(size).timeout(timeout);
      switch (header['compression']) {
        case null:
          break;
        case 'gzip':
          body = Uint8List.fromList(gzip.decode(body));
        default:
          throw RepoException(
              'unsupported compression ${header['compression']}');
      }
      return _Response(header, body);
    } finally {
      socket.destroy();
    }
  }

  Future<SecureSocket> _connect() async {
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(lichRepoCaPem));

    // The server cert's CN is not the hostname, so normal hostname
    // verification always fails. Like repository.lic, accept it only if it
    // was signed by the pinned CA, is in date, and has a known CN.
    final now = DateTime.now();
    final socket = await SecureSocket.connect(
      host,
      port,
      context: context,
      timeout: timeout,
      onBadCertificate: (cert) =>
          _verifier.isSignedByCa(cert.der) &&
          now.isAfter(cert.startValidity) &&
          now.isBefore(cert.endValidity) &&
          _allowedCns.contains(_cn(cert.subject)),
    );
    final cn = _cn(socket.peerCertificate?.subject ?? '');
    if (!_allowedCns.contains(cn)) {
      socket.destroy();
      throw RepoException('server certificate CN mismatch: $cn');
    }
    return socket;
  }

  static final _verifier = PinnedCaVerifier(lichRepoCaPem);

  static String? _cn(String subject) =>
      RegExp(r'CN=([^/,]+)').firstMatch(subject)?.group(1);

  // ---------------------------------------------------------------------------
  // Pure parsing helpers (public for tests)

  static String encodeRequest(Map<String, String> fields) =>
      fields.entries.expand((e) => [e.key, e.value]).join('\t');

  /// Parses a `key\tvalue\tkey\tvalue` header line; keys are lowercased.
  static Map<String, String> decodeHeader(String line) {
    final parts = line.replaceAll(RegExp(r'[\r\n]+$'), '').split('\t');
    return {
      for (var i = 0; i + 1 < parts.length; i += 2)
        parts[i].toLowerCase(): parts[i + 1],
    };
  }

  /// Parses the `list` body (tab-separated, header row first) and merges the
  /// `list-comments` body into it. `last update` is server epoch seconds;
  /// [serverTime] corrects for clock skew the same way repository.lic does.
  static List<CatalogEntry> parseList(
    String data, {
    String? comments,
    int? serverTime,
  }) {
    final lines = data.split('\n').where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return [];
    final headers = lines.first.split('\t');
    int? col(String name) {
      final i = headers.indexOf(name);
      return i < 0 ? null : i;
    }

    final commentMap = <String, String>{};
    if (comments != null) {
      final clines = comments.split('\n').where((l) => l.isNotEmpty).toList();
      if (clines.isNotEmpty) {
        final ch = clines.first.split('\t');
        final fi = ch.indexOf('file'), gi = ch.indexOf('game');
        final ci = ch.indexOf('comments');
        for (final line in clines.skip(1)) {
          final r = line.split('\t');
          if (fi < 0 || ci < 0 || ci >= r.length) continue;
          final key = '${r[fi]}\u0000${gi >= 0 ? r[gi] : ''}';
          final text =
              r[ci].replaceAll('\x14', '\t').replaceAll('\x12', '\n').trim();
          if (text.isNotEmpty) commentMap[key] = text;
        }
      }
    }

    final skew = serverTime == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch ~/ 1000 - serverTime;

    return [
      for (final line in lines.skip(1))
        () {
          final r = line.split('\t');
          String? get(String name) {
            final i = col(name);
            if (i == null || i >= r.length || r[i].isEmpty) return null;
            return r[i];
          }

          int? getInt(String name) => int.tryParse(get(name) ?? '');
          final name = get('file') ?? '';
          final game = get('game');
          final updated = getInt('last update');
          return CatalogEntry(
            sourceId: 'lich',
            name: name,
            game: game,
            author: get('author'),
            tags: (get('tags') ?? '')
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)
                .toList(),
            lastUpdated: updated == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch((updated + skew) * 1000),
            size: getInt('size'),
            downloads: getInt('downloads'),
            ratingTotal: getInt('rating total'),
            ratingCount: getInt('rating count'),
            comments: commentMap['$name\u0000${game ?? ''}'],
          );
        }(),
    ];
  }
}

class _Response {
  _Response(this.header, this.body);
  final Map<String, String> header;
  final Uint8List body;
}

/// Buffers a socket stream so we can read one line, then N raw bytes.
class _SocketReader {
  _SocketReader(Stream<List<int>> stream) {
    _sub = stream.listen(
      (chunk) {
        _buf.add(chunk);
        _pump();
      },
      onDone: () {
        _done = true;
        _pump();
      },
      onError: (Object e) {
        _error = e;
        _pump();
      },
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final _buf = BytesBuilder();
  bool _done = false;
  Object? _error;
  bool Function()? _waiter;

  Future<String> readLine() => _wait(() {
        final bytes = _buf.toBytes();
        final nl = bytes.indexOf(10);
        if (nl < 0) return null;
        _consume(bytes, nl + 1);
        return utf8.decode(bytes.sublist(0, nl), allowMalformed: true);
      });

  Future<Uint8List> readBytes(int n) => _wait(() {
        final bytes = _buf.toBytes();
        if (bytes.length < n) return null;
        _consume(bytes, n);
        return Uint8List.sublistView(bytes, 0, n);
      });

  void _consume(Uint8List bytes, int n) {
    _buf.clear();
    _buf.add(bytes.sublist(n));
  }

  Future<T> _wait<T>(T? Function() attempt) {
    final c = Completer<T>();
    bool tryIt() {
      final v = attempt();
      if (v != null) {
        c.complete(v);
        return true;
      }
      if (_error != null) {
        c.completeError(_error!);
        return true;
      }
      if (_done) {
        c.completeError(RepoException('connection closed early'));
        return true;
      }
      return false;
    }

    if (!tryIt()) _waiter = tryIt;
    return c.future.whenComplete(() {
      if (_done) _sub.cancel();
    });
  }

  void _pump() {
    final w = _waiter;
    if (w != null && w()) _waiter = null;
  }
}
