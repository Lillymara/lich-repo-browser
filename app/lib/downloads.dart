import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:repo_core/repo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a local copy compares to a catalog entry.
enum InstallStatus { notInstalled, same, different, unknown }

/// Where downloads go, and saving/inspecting files there.
class Downloads {
  Downloads(this._prefs, {this.autodetect = true});

  final SharedPreferences? _prefs;

  /// Whether to look for an existing Lich install (off in tests).
  final bool autodetect;
  static const _key = 'downloadDir';

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// The folder downloads are saved to: the user's choice, else a detected
  /// Lich `scripts` folder, else (mobile) the app's documents folder.
  Future<String?> folder() async {
    final saved = _prefs?.getString(_key);
    if (saved != null && Directory(saved).existsSync()) return saved;
    final detected = autodetect ? detectLichScripts() : null;
    if (detected != null) return detected;
    if (isMobile) return (await getApplicationDocumentsDirectory()).path;
    return null;
  }

  Future<void> setFolder(String path) async => _prefs?.setString(_key, path);

  /// Looks for a Lich install in the usual places.
  static String? detectLichScripts() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final candidates = [
      if (home != null)
        for (final name in ['Lich5', 'lich5', 'Lich', 'lich'])
          '$home${Platform.pathSeparator}$name${Platform.pathSeparator}scripts',
      if (Platform.isWindows) ...[r'C:\Lich5\scripts', r'C:\Lich\scripts'],
    ];
    return candidates.where((p) => Directory(p).existsSync()).firstOrNull;
  }

  File fileFor(String folder, CatalogEntry entry) =>
      File('$folder${Platform.pathSeparator}${entry.name}');

  /// Compares the local copy against [entry]: Jinx publishes a SHA-1, the
  /// Lich repo only a size, so a size match there is reported as [unknown].
  Future<InstallStatus> status(String folder, CatalogEntry entry) async {
    final f = fileFor(folder, entry);
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

  Future<File> save(
    String folder,
    RepoSource source,
    CatalogEntry entry, {
    String? version,
  }) async {
    final bytes = await source.download(entry, version: version);
    final f = fileFor(folder, entry);
    // Write to a temp file first so a failed download never truncates an
    // existing script.
    final tmp = File('${f.path}.download');
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp.rename(f.path);
  }
}
