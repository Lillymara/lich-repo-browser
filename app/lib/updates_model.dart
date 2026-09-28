import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:repo_core/repo_core.dart';

import 'catalog_model.dart';
import 'downloads.dart';

enum UpdateState {
  /// Matches the newest copy any source offers.
  upToDate,

  /// A newer version exists (or the file matches an older published copy).
  updateAvailable,

  /// Differs from every source, and its version isn't older: likely edited.
  modified,

  /// Differs, and there's no version or date to say which is newer.
  differs,
}

/// Facts about a file on disk, computed off the UI thread.
class LocalFile {
  LocalFile({
    required this.path,
    required this.sha1,
    required this.size,
    required this.modified,
    this.version,
  });

  final String path;
  final String sha1;
  final int size;
  final DateTime modified;
  final String? version;
}

class InstalledItem {
  InstalledItem({
    required this.group,
    required this.local,
    required this.latest,
    required this.state,
    this.remoteVersion,
  });

  final ScriptGroup group;
  final LocalFile local;

  /// The copy an update would install.
  final CatalogEntry latest;
  final UpdateState state;
  final String? remoteVersion;

  bool get canUpdate => state != UpdateState.upToDate;
}

/// Newest entry among [entries]: by version when both have one, otherwise
/// by last-updated date. Entries from [archives] (snapshot repos whose dates
/// are the snapshot date) only count when nothing else has the file.
CatalogEntry pickLatest(
  List<CatalogEntry> entries, {
  Set<String> archives = const {},
}) {
  final live = entries.where((e) => !archives.contains(e.sourceId)).toList();
  if (live.isNotEmpty) entries = live;
  int cmp(CatalogEntry a, CatalogEntry b) {
    if (a.version != null && b.version != null) {
      final c = compareVersions(a.version!, b.version!);
      if (c != 0) return c;
    }
    final ta = a.lastUpdated?.millisecondsSinceEpoch ?? 0;
    final tb = b.lastUpdated?.millisecondsSinceEpoch ?? 0;
    if (ta != tb) return ta.compareTo(tb);
    // Same date: prefer an entry that can be verified by hash.
    return (a.sha1Hex != null ? 1 : 0) - (b.sha1Hex != null ? 1 : 0);
  }

  return entries.reduce((a, b) => cmp(b, a) > 0 ? b : a);
}

/// The version of [latest], borrowing it from a same-day Jinx entry when
/// [latest] is from the Lich repo (which doesn't publish versions).
String? latestVersion(CatalogEntry latest, List<CatalogEntry> entries) {
  if (latest.version != null) return latest.version;
  final day = latest.lastUpdated;
  if (day == null) return null;
  return entries
      .where(
        (e) =>
            e.version != null &&
            e.lastUpdated != null &&
            e.lastUpdated!.difference(day).inHours.abs() < 24,
      )
      .map((e) => e.version!)
      .firstOrNull;
}

/// Decides the status of a local file. Jinx entries are compared by hash.
/// The Lich repo list only gives a size (per-file hashes would take one
/// server connection each, which its rate limit doesn't allow), so a
/// matching size counts as the same file.
UpdateState decideState({
  required LocalFile local,
  required List<CatalogEntry> entries,
  required CatalogEntry latest,
  Set<String> archives = const {},
}) {
  final matchesLatest = latest.sha1Hex != null
      ? latest.sha1Hex == local.sha1
      : latest.size != null && latest.size == local.size;
  if (matchesLatest) return UpdateState.upToDate;

  // Identical to some other (older) published copy.
  if (entries.any((e) => e != latest && e.sha1Hex == local.sha1)) {
    return UpdateState.updateAvailable;
  }

  final remote = latestVersion(latest, entries);
  if (local.version != null && remote != null) {
    return compareVersions(local.version!, remote) < 0
        ? UpdateState.updateAvailable
        : UpdateState.modified;
  }
  // An archive's date is when the snapshot was taken, so it says nothing
  // about which copy is newer.
  final updated = archives.contains(latest.sourceId)
      ? null
      : latest.lastUpdated;
  if (updated != null && local.modified.isBefore(updated)) {
    return UpdateState.updateAvailable;
  }
  return UpdateState.differs;
}

/// Finds catalog files that exist in the Lich folder and checks each one.
class UpdatesModel extends ChangeNotifier {
  UpdatesModel(this.catalog, this.downloads);

  final CatalogModel catalog;
  final Downloads downloads;

  List<InstalledItem> items = const [];
  LichFolder? folder;
  bool scanning = false;
  DateTime? scannedAt;
  String? progress;

  int get updateCount => items.where((i) => i.canUpdate).length;

  Set<String> get _archives => {
    for (final s in catalog.sources)
      if (s.source case JinxSource(archive: true)) s.source.id,
  };

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    progress = 'Looking for installed files…';
    notifyListeners();
    try {
      folder = await downloads.folder();
      items = folder == null ? const [] : await _scan(folder!);
      scannedAt = DateTime.now();
      _publishInstalled();
    } finally {
      scanning = false;
      progress = null;
      notifyListeners();
    }
  }

  Future<List<InstalledItem>> _scan(LichFolder folder) async {
    // Directory listings, keyed by lowercase name (Windows/macOS are
    // case-insensitive; Linux isn't, so keep the real name).
    final listings = <String, Map<String, String>>{};
    Map<String, String> list(String dir) => listings.putIfAbsent(dir, () {
      final d = Directory(dir);
      if (!d.existsSync()) return const {};
      return {
        for (final f in d.listSync().whereType<File>())
          f.uri.pathSegments.last.toLowerCase(): f.path,
      };
    });

    // Match groups to local files. Map images and engine files are left out,
    // as jinx's auto-update does.
    final found = <(ScriptGroup, String)>[];
    for (final g in catalog.allGroups) {
      if (g.type == 'map' || g.type == 'engine') continue;
      for (final e in g.entries) {
        final path = list(folder.dirFor(e))[e.name.toLowerCase()];
        if (path != null) {
          found.add((g, path));
          break;
        }
      }
    }

    progress = 'Checking ${found.length} files…';
    notifyListeners();
    final locals = await _inspectAll([for (final (_, path) in found) path]);

    final archives = _archives;

    final out = <InstalledItem>[];
    for (var i = 0; i < found.length; i++) {
      final g = found[i].$1;
      final latest = pickLatest(g.entries, archives: archives);
      out.add(
        InstalledItem(
          group: g,
          local: locals[i],
          latest: latest,
          remoteVersion: latestVersion(latest, g.entries),
          state: decideState(
            local: locals[i],
            entries: g.entries,
            latest: latest,
            archives: archives,
          ),
        ),
      );
    }
    // Updates first, then alphabetical.
    out.sort((a, b) {
      final c = (b.canUpdate ? 1 : 0) - (a.canUpdate ? 1 : 0);
      return c != 0
          ? c
          : a.group.name.toLowerCase().compareTo(b.group.name.toLowerCase());
    });
    return out;
  }

  /// Lets Browse mark and filter installed / outdated files.
  void _publishInstalled() => catalog.setInstalled({
    for (final i in items) i.group.name.toLowerCase(): i.canUpdate,
  });

  /// Installs [item.latest], replacing the local copy (backed up first).
  Future<({File file, String? backup})> update(InstalledItem item) async {
    final f = folder ?? await downloads.folder();
    if (f == null) throw StateError('No Lich folder set');
    final source = catalog.stateFor(item.latest.sourceId).source;
    // Overwrite the file we found, even if its name differs in case.
    final result = await downloads.save(
      f,
      source,
      item.latest,
      target: File(item.local.path),
    );
    await _refreshOne(item);
    return result;
  }

  Future<void> _refreshOne(InstalledItem item) async {
    final path = item.local.path;
    final local = (await _inspectAll([path])).single;
    final updated = InstalledItem(
      group: item.group,
      local: local,
      latest: item.latest,
      remoteVersion: item.remoteVersion,
      state: decideState(
        local: local,
        entries: item.group.entries,
        latest: item.latest,
        archives: _archives,
      ),
    );
    items = [for (final i in items) identical(i, item) ? updated : i];
    _publishInstalled();
    notifyListeners();
  }
}

/// Inspects [paths] on a background isolate. Top-level on purpose: a closure
/// inside a method would capture `this` (and its sockets), which can't be
/// sent to another isolate.
Future<List<LocalFile>> _inspectAll(List<String> paths) =>
    Isolate.run(() => [for (final p in paths) _inspect(p)]);

/// Hashes a file and pulls the version from its header. Runs in an isolate.
LocalFile _inspect(String path) {
  final f = File(path);
  final bytes = f.readAsBytesSync();
  String? version;
  if (RegExp(r'\.(lic|rb|cmd)$', caseSensitive: false).hasMatch(path)) {
    // Only the start of the file can hold the header.
    final head = utf8.decode(
      bytes.length > 64 * 1024 ? bytes.sublist(0, 64 * 1024) : bytes,
      allowMalformed: true,
    );
    version = parseScriptVersion(extractScriptHeader(head));
  }
  return LocalFile(
    path: path,
    sha1: sha1.convert(bytes).toString(),
    size: bytes.length,
    modified: f.lastModifiedSync(),
    version: version,
  );
}
