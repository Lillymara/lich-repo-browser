import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repo_core/repo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a local copy compares to a catalog entry.
enum InstallStatus { notInstalled, same, different, unknown }

final _sep = Platform.pathSeparator;

/// A Lich install (or, on phones, a flat app folder) and where each kind of
/// file belongs in it. Mirrors repository.lic / jinx.lic:
///   scripts -> scripts/, data -> data/, map images -> maps/,
///   engine  -> the Lich folder itself.
class LichFolder {
  LichFolder(this.root, {this.flat = false});

  final String root;

  /// Everything goes straight into [root] (mobile, where there's no Lich).
  final bool flat;

  static const _dataExtensions = {'ui', 'xml', 'json', 'yaml', 'yml'};

  String get scriptsDir => flat ? root : '$root${_sep}scripts';
  String get dataDir => flat ? root : '$root${_sep}data';
  String get mapsDir => flat ? root : '$root${_sep}maps';

  String dirFor(CatalogEntry e) {
    if (flat) return root;
    final ext = e.name.contains('.')
        ? e.name.split('.').last.toLowerCase()
        : '';
    return switch (e.type) {
      'map' => mapsDir,
      'data' => dataDir,
      'engine' => root,
      // The Lich repo lists everything as "script"; repository.lic routes
      // these extensions to data/.
      _ when e.sourceId == 'lich' && _dataExtensions.contains(ext) => dataDir,
      _ => scriptsDir,
    };
  }

  File fileFor(CatalogEntry e) => File('${dirFor(e)}$_sep${e.name}');

  /// Where old copies go before being replaced: `<lich>/temp/...`, which is
  /// Lich's own scratch folder.
  String get backupRoot => '$root${_sep}temp${_sep}repo-browser-backups';
}

/// Where downloads go, and saving/inspecting files there.
class Downloads {
  Downloads(this._prefs, {this.autodetect = true});

  final SharedPreferences? _prefs;

  /// Whether to look for an existing Lich install (off in tests).
  final bool autodetect;

  static const _key = 'lichDir';
  static const _legacyKey = 'downloadDir'; // phase 2 stored the scripts dir

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// The Lich folder: the user's choice, else a detected install, else
  /// (mobile) the app's documents folder.
  Future<LichFolder?> folder() async {
    if (isMobile) {
      return LichFolder(
        (await getApplicationDocumentsDirectory()).path,
        flat: true,
      );
    }
    final legacy = _prefs?.getString(_legacyKey);
    final saved =
        _prefs?.getString(_key) ??
        (legacy == null ? null : normalizeRoot(legacy));
    if (saved != null && Directory(saved).existsSync()) {
      return LichFolder(saved);
    }
    final detected = autodetect ? detectLich() : null;
    return detected == null ? null : LichFolder(detected);
  }

  Future<void> setRoot(String path) async =>
      _prefs?.setString(_key, normalizeRoot(path));

  /// If the user picked Lich's `scripts` folder, use its parent.
  static String normalizeRoot(String path) {
    final trimmed = path.endsWith(_sep)
        ? path.substring(0, path.length - 1)
        : path;
    final name = trimmed.split(_sep).last.toLowerCase();
    return name == 'scripts' ? Directory(trimmed).parent.path : trimmed;
  }

  /// Looks for a Lich install (a folder containing `scripts/`).
  static String? detectLich() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final candidates = [
      if (home != null)
        for (final name in ['Lich5', 'lich5', 'Lich', 'lich'])
          '$home$_sep$name',
      if (Platform.isWindows) ...[r'C:\Lich5', r'C:\Lich'],
    ];
    return candidates
        .where((p) => Directory('$p${_sep}scripts').existsSync())
        .firstOrNull;
  }

  /// Compares the local copy against [entry]: Jinx publishes a SHA-1, the
  /// Lich repo list only a size, so a size match there is [unknown].
  Future<InstallStatus> status(LichFolder folder, CatalogEntry entry) async {
    final f = folder.fileFor(entry);
    if (!await f.exists()) return InstallStatus.notInstalled;
    if (entry.sha1Hex != null) {
      final digest = sha1.convert(await f.readAsBytes()).toString();
      return digest == entry.sha1Hex
          ? InstallStatus.same
          : InstallStatus.different;
    }
    if (entry.size != null && await f.length() != entry.size) {
      return InstallStatus.different;
    }
    return InstallStatus.unknown;
  }

  /// Downloads [entry] into [folder] (or over [target], an existing file
  /// whose name may differ in case). If that replaces a different existing
  /// file, the old copy is first saved to a timestamped backup folder
  /// (desktop only); its path is returned as `backup`.
  Future<({File file, String? backup})> save(
    LichFolder folder,
    RepoSource source,
    CatalogEntry entry, {
    String? version,
    File? target,
  }) async {
    final bytes = await source.download(entry, version: version);
    final f = target ?? folder.fileFor(entry);
    await f.parent.create(recursive: true);

    String? backup;
    if (!folder.flat && await f.exists()) {
      final old = await f.readAsBytes();
      if (!_sameBytes(old, bytes)) {
        final dir = Directory('${folder.backupRoot}$_sep${_stamp()}');
        await dir.create(recursive: true);
        backup = (await f.copy('${dir.path}$_sep${f.uri.pathSegments.last}'))
            .path;
      }
    }

    // Write to a temp file first so a failed download never truncates an
    // existing file.
    final tmp = File('${f.path}.download');
    await tmp.writeAsBytes(bytes, flush: true);
    return (file: await tmp.rename(f.path), backup: backup);
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _stamp() {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
