import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/downloads.dart';
import 'package:lich_repo_browser/updates_model.dart';
import 'package:repo_core/repo_core.dart';

class BytesSource implements RepoSource {
  BytesSource(this.id, this.files);
  @override
  final String id;
  final Map<String, List<int>> files;
  @override
  String get displayName => id;
  @override
  Future<List<CatalogEntry>> fetchCatalog() async => [
    for (final e in files.entries)
      CatalogEntry(
        sourceId: id,
        name: e.key,
        sha1Hex: sha1.convert(e.value).toString(),
        version: '2.0',
        lastUpdated: DateTime(2026, 1, 1),
      ),
  ];
  @override
  Future<EntryDetails> fetchDetails(CatalogEntry entry) async =>
      EntryDetails(text: '');
  @override
  Future<Uint8List> download(CatalogEntry entry, {String? version}) async =>
      Uint8List.fromList(files[entry.name]!);
}

LocalFile local(String content, {String? version, DateTime? modified}) {
  final bytes = utf8.encode(content);
  return LocalFile(
    path: '/x',
    sha1: sha1.convert(bytes).toString(),
    size: bytes.length,
    modified: modified ?? DateTime(2025, 6, 1),
    version: version,
  );
}

String sha(String s) => sha1.convert(utf8.encode(s)).toString();

void main() {
  group('pickLatest', () {
    test('prefers higher version, then newer date', () {
      final a = CatalogEntry(sourceId: 'jinx:a', name: 'x', version: '1.9');
      final b = CatalogEntry(sourceId: 'jinx:b', name: 'x', version: '1.10');
      expect(pickLatest([a, b]), b);
      final lich = CatalogEntry(
        sourceId: 'lich',
        name: 'x',
        lastUpdated: DateTime(2026),
      );
      final mirror = CatalogEntry(
        sourceId: 'jinx:mirror',
        name: 'x',
        version: '0.1',
        lastUpdated: DateTime(2020),
      );
      expect(pickLatest([mirror, lich]), lich);
    });
  });

  test('archive entries only win when nothing else has the file', () {
    final lich = CatalogEntry(
      sourceId: 'lich',
      name: 'x',
      lastUpdated: DateTime(2019),
    );
    final mirror = CatalogEntry(
      sourceId: 'jinx:mirror',
      name: 'x',
      lastUpdated: DateTime(2020),
    );
    expect(pickLatest([lich, mirror], archives: {'jinx:mirror'}), lich);
    expect(pickLatest([mirror], archives: {'jinx:mirror'}), mirror);
    // ...and their snapshot date isn't evidence of an update.
    expect(
      decideState(
        local: local('mine', modified: DateTime(2019)),
        entries: [mirror],
        latest: mirror,
        archives: {'jinx:mirror'},
      ),
      UpdateState.differs,
    );
  });

  group('decideState', () {
    final jinx = CatalogEntry(
      sourceId: 'jinx:eo',
      name: 'a.lic',
      version: '2.0',
      sha1Hex: sha('new'),
      lastUpdated: DateTime(2026, 1, 1),
    );
    final mirror = CatalogEntry(
      sourceId: 'jinx:mirror',
      name: 'a.lic',
      version: '1.0',
      sha1Hex: sha('old'),
      lastUpdated: DateTime(2020),
    );

    UpdateState decide(LocalFile f) => decideState(
      local: f,
      entries: [jinx, mirror],
      latest: pickLatest([jinx, mirror]),
    );

    test('matching the newest copy is up to date', () {
      expect(decide(local('new')), UpdateState.upToDate);
    });
    test('matching an older published copy needs an update', () {
      expect(decide(local('old')), UpdateState.updateAvailable);
    });
    test('older header version needs an update', () {
      expect(
        decide(local('edited', version: '1.5')),
        UpdateState.updateAvailable,
      );
    });
    test('same or newer version but different bytes is modified', () {
      expect(decide(local('edited', version: '2.0')), UpdateState.modified);
      expect(decide(local('edited', version: '2.1')), UpdateState.modified);
    });
    test('no version: falls back to dates', () {
      expect(
        decide(local('?', modified: DateTime(2025))),
        UpdateState.updateAvailable,
      );
      expect(
        decide(local('?', modified: DateTime(2026, 6))),
        UpdateState.differs,
      );
    });
    test('Lich repo entries are compared by size', () {
      final f = local('content'); // 7 bytes
      CatalogEntry lich(int size) => CatalogEntry(
        sourceId: 'lich',
        name: 'b.lic',
        size: size,
        lastUpdated: DateTime(2026),
      );
      expect(
        decideState(local: f, entries: [lich(7)], latest: lich(7)),
        UpdateState.upToDate,
      );
      expect(
        decideState(local: f, entries: [lich(9)], latest: lich(9)),
        UpdateState.updateAvailable, // local is older than 2026
      );
    });
  });

  group('LichFolder', () {
    final f = LichFolder('/lich');
    String dir(String name, {String source = 'lich', String type = 'script'}) =>
        f.dirFor(CatalogEntry(sourceId: source, name: name, type: type));

    test('routes files like repository.lic and jinx.lic', () {
      expect(dir('bigshot.lic'), '/lich/scripts');
      expect(dir('layout.xml'), '/lich/data');
      expect(dir('settings.YAML'), '/lich/data');
      expect(dir('thing.rb'), '/lich/scripts');
      expect(
        dir('effect-list.xml', source: 'jinx:eo', type: 'data'),
        '/lich/data',
      );
      expect(dir('town.png', source: 'jinx:maps', type: 'map'), '/lich/maps');
      expect(dir('lich.rbw', source: 'jinx:eo', type: 'engine'), '/lich');
    });

    test('flat folders (mobile) keep everything together', () {
      final flat = LichFolder('/docs', flat: true);
      expect(
        flat.dirFor(CatalogEntry(sourceId: 'lich', name: 'x.xml')),
        '/docs',
      );
    });

    test('picking the scripts folder means its parent', () {
      expect(
        Downloads.normalizeRoot('/home/me/Lich5/scripts'),
        '/home/me/Lich5',
      );
      expect(Downloads.normalizeRoot('/home/me/Lich5/'), '/home/me/Lich5');
    });
  });

  group('with a temporary Lich folder', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lich-test');
      await Directory('${tmp.path}/scripts').create();
      await Directory('${tmp.path}/data').create();
    });
    tearDown(() => tmp.delete(recursive: true));

    test('save backs up a replaced file, but not an identical one', () async {
      final source = BytesSource('jinx:eo', {'a.lic': utf8.encode('new')});
      final entry = (await source.fetchCatalog()).single;
      final folder = LichFolder(tmp.path);
      final downloads = Downloads(null, autodetect: false);
      final target = File('${tmp.path}/scripts/a.lic');
      await target.writeAsString('old');

      final r = await downloads.save(folder, source, entry);
      expect(await target.readAsString(), 'new');
      expect(r.backup, isNotNull);
      expect(await File(r.backup!).readAsString(), 'old');
      expect(r.backup, startsWith(folder.backupRoot));
      expect(File('${target.path}.download').existsSync(), isFalse);

      final again = await downloads.save(folder, source, entry);
      expect(again.backup, isNull);
    });

    test('scan finds installed files and update installs them', () async {
      final source = BytesSource('jinx:eo', {
        'current.lic': utf8.encode('same'),
        'stale.lic': utf8.encode('fresh'),
        'notinstalled.lic': utf8.encode('x'),
      });
      await File('${tmp.path}/scripts/current.lic').writeAsString('same');
      await File('${tmp.path}/scripts/STALE.lic')
          .writeAsString('# version: 1.0\nold');
      await File('${tmp.path}/scripts/unrelated.lic').writeAsString('mine');

      final catalog = CatalogModel(sources: [source]);
      await catalog.refresh();
      final updates = UpdatesModel(
        catalog,
        _FixedDownloads(LichFolder(tmp.path)),
      );
      await updates.scan();

      final byName = {for (final i in updates.items) i.group.name: i};
      expect(byName.keys, unorderedEquals(['current.lic', 'stale.lic']));
      expect(byName['current.lic']!.state, UpdateState.upToDate);
      expect(byName['stale.lic']!.state, UpdateState.updateAvailable);
      expect(byName['stale.lic']!.local.version, '1.0');
      expect(updates.updateCount, 1);

      await updates.update(byName['stale.lic']!);
      expect(updates.updateCount, 0);
      // The existing file was replaced in place, not duplicated.
      expect(
        await File('${tmp.path}/scripts/STALE.lic').readAsString(),
        'fresh',
      );
      expect(
        File('${tmp.path}/scripts/stale.lic').existsSync(),
        Platform.isLinux ? isFalse : isTrue,
      );
    });
  });

  group('catalog cache', () {
    test('round-trips and survives a failed refresh', () async {
      final dir = await Directory.systemTemp.createTemp('lich-cache');
      addTearDown(() => dir.delete(recursive: true));
      final online = CatalogModel(
        sources: [
          BytesSource('jinx:eo', {'a.lic': utf8.encode('x')}),
        ],
        cacheDir: dir,
      );
      await online.refresh();
      // Let the fire-and-forget cache write land.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final offline = CatalogModel(
        sources: [_FailingSource('jinx:eo')],
        cacheDir: dir,
      );
      await offline.loadCached();
      expect(offline.allGroups.map((g) => g.name), ['a.lic']);
      expect(offline.stateFor('jinx:eo').fromCache, isTrue);

      await offline.refresh();
      final s = offline.stateFor('jinx:eo');
      expect(s.state, LoadState.error);
      expect(offline.allGroups.map((g) => g.name), [
        'a.lic',
      ], reason: 'cached entries are kept when offline');
    });
  });
}

class _FixedDownloads extends Downloads {
  _FixedDownloads(this._folder) : super(null, autodetect: false);
  final LichFolder _folder;
  @override
  Future<LichFolder?> folder() async => _folder;
}

class _FailingSource implements RepoSource {
  _FailingSource(this.id);
  @override
  final String id;
  @override
  String get displayName => id;
  @override
  Future<List<CatalogEntry>> fetchCatalog() async =>
      throw RepoException('offline');
  @override
  Future<EntryDetails> fetchDetails(CatalogEntry entry) async =>
      throw UnimplementedError();
  @override
  Future<Uint8List> download(CatalogEntry entry, {String? version}) async =>
      throw UnimplementedError();
}
