import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'catalog_entry.dart';
import 'source.dart';

/// A Jinx repository: a static HTTPS site with `/manifest.json`.
class JinxSource implements RepoSource {
  JinxSource({
    required this.name,
    required this.baseUrl,
    this.game,
    this.archive = false,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  /// Default repos from jinx.lic (deprecated `core` and `gtk3` omitted).
  static List<JinxSource> defaults() => [
        JinxSource(
            name: 'elanthia-online',
            baseUrl: 'https://extras.repo.elanthia.online'),
        JinxSource(
            name: 'mirror',
            baseUrl: 'https://ffnglichrepoarchive.netlify.app',
            archive: true),
        JinxSource(
            name: 'mapdb-backup-gs',
            baseUrl: 'https://elanthia-online.github.io/mapdb-backup-gs',
            game: 'gs'),
        JinxSource(
            name: 'mapdb-backup-dr',
            baseUrl: 'https://elanthia-online.github.io/mapdb-backup-dr',
            game: 'dr'),
      ];

  final String name;
  final String baseUrl;

  /// Game every entry belongs to, when the whole repo is game-specific.
  /// Jinx manifests don't carry a game themselves.
  final String? game;

  /// A frozen snapshot of another repo: every entry carries the snapshot
  /// date, not when the script really changed, so it shouldn't be treated as
  /// the newest copy of anything available elsewhere.
  final bool archive;
  final HttpClient _client;

  /// Absolute URL for a manifest path such as [CatalogEntry.path].
  Uri urlFor(String path) => Uri.parse('$baseUrl$path');

  @override
  String get id => 'jinx:$name';

  @override
  String get displayName => 'Jinx: $name';

  @override
  Future<List<CatalogEntry>> fetchCatalog() async =>
      parseManifest(id, utf8.decode(await _get('/manifest.json')), game: game);

  @override
  Future<EntryDetails> fetchDetails(CatalogEntry entry) async {
    if (entry.headerPath == null) return EntryDetails(text: '');
    return EntryDetails(
        text: utf8.decode(await _get(entry.headerPath!), allowMalformed: true));
  }

  @override
  Future<Uint8List> download(CatalogEntry entry, {String? version}) {
    if (version != null) {
      throw RepoException('Jinx repos only serve the latest version');
    }
    return _get(entry.path!);
  }

  Future<Uint8List> _get(String path) async {
    final req = await _client.getUrl(urlFor(path));
    final res = await req.close();
    final bytes = await res.fold<BytesBuilder>(
        BytesBuilder(), (b, chunk) => b..add(chunk));
    if (res.statusCode != 200) {
      throw RepoException('GET $baseUrl$path -> HTTP ${res.statusCode}');
    }
    return bytes.takeBytes();
  }

  /// Parses a Jinx `manifest.json` into entries.
  static List<CatalogEntry> parseManifest(String sourceId, String json,
      {String? game}) {
    final decoded = jsonDecode(json);
    final available = decoded is Map ? decoded['available'] : null;
    if (available is! List) {
      throw RepoException('manifest has no "available" list');
    }
    return [
      for (final a in available.whereType<Map>())
        CatalogEntry(
          sourceId: sourceId,
          name:
              Uri.decodeComponent((a['file'] as String? ?? '').split('/').last),
          type: a['type'] as String? ?? 'script',
          game: game,
          author: a['author'] as String?,
          version: a['version']?.toString(),
          tags: [for (final t in (a['tags'] as List? ?? const [])) '$t'],
          lastUpdated: a['last_commit'] is int
              ? DateTime.fromMillisecondsSinceEpoch(
                  (a['last_commit'] as int) * 1000)
              : null,
          sha1Hex: _b64ToHex(a['md5'] as String?),
          path: a['file'] as String?,
          headerPath: a['header'] as String?,
        ),
    ];
  }

  static String? _b64ToHex(String? b64) {
    if (b64 == null) return null;
    try {
      return base64
          .decode(b64)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    } on FormatException {
      return null;
    }
  }
}
