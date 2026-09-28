import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/downloads.dart';
import 'package:lich_repo_browser/main.dart';
import 'package:lich_repo_browser/updates_model.dart';
import 'package:repo_core/repo_core.dart';

/// In-memory source so tests never touch the network.
class FakeSource implements RepoSource {
  FakeSource(this.id, this.entries, {this.fail = false});

  @override
  final String id;
  final List<CatalogEntry> entries;
  final bool fail;

  @override
  String get displayName => 'Fake $id';

  @override
  Future<List<CatalogEntry>> fetchCatalog() async {
    if (fail) throw RepoException('offline');
    return entries;
  }

  @override
  Future<EntryDetails> fetchDetails(CatalogEntry entry) async =>
      EntryDetails(text: 'Header for ${entry.name}', versions: ['1.0']);

  @override
  Future<Uint8List> download(CatalogEntry entry, {String? version}) async =>
      Uint8List(0);
}

CatalogEntry lich(
  String name, {
  String game = 'gs',
  int downloads = 0,
  List<String> tags = const [],
}) => CatalogEntry(
  sourceId: 'lich',
  name: name,
  game: game,
  author: 'Author',
  downloads: downloads,
  tags: tags,
  lastUpdated: DateTime(2026, 1, 1),
);

CatalogEntry jinx(String name, {String type = 'script', String? version}) =>
    CatalogEntry(
      sourceId: 'jinx:extras',
      name: name,
      type: type,
      version: version,
      headerPath: '/headers/$name',
    );

CatalogModel fakeModel({bool jinxFails = false}) => CatalogModel(
  sources: [
    FakeSource('lich', [
      lich('bigshot.lic', downloads: 900, tags: ['hunting']),
      lich('drscript.lic', game: 'dr', downloads: 5),
      lich('anyscript.lic', game: 'any', downloads: 50),
    ]),
    FakeSource('jinx:extras', [
      jinx('bigshot.lic', version: '5.16.5'),
      jinx('jinxonly.lic', version: '1.0'),
      jinx('town.png', type: 'map'),
    ], fail: jinxFails),
  ],
);

void main() {
  group('CatalogModel', () {
    test('groups the same file across sources', () async {
      final m = fakeModel();
      await m.refresh();
      final names = m.visible.map((g) => g.name).toList();
      expect(names, [
        'anyscript.lic',
        'bigshot.lic',
        'drscript.lic',
        'jinxonly.lic',
      ]);
      final big = m.visible.firstWhere((g) => g.name == 'bigshot.lic');
      expect(big.entries.map((e) => e.sourceId), ['lich', 'jinx:extras']);
      expect(big.version, '5.16.5');
      expect(big.downloads, 900);
    });

    test('filters by game, type, search and source', () async {
      final m = fakeModel();
      await m.refresh();

      m.setGameFilter(GameFilter.dr);
      expect(m.visible.map((g) => g.name), [
        'anyscript.lic',
        'drscript.lic',
        'jinxonly.lic',
      ]);
      m.setGameFilter(GameFilter.all);

      m.setTypeFilter(TypeFilter.maps);
      expect(m.visible.map((g) => g.name), ['town.png']);
      m.setTypeFilter(TypeFilter.scripts);

      m.setQuery('hunt');
      expect(m.visible.map((g) => g.name), ['bigshot.lic']);
      m.setQuery('');

      m.setSourceEnabled(m.stateFor('jinx:extras'), false);
      expect(m.visible.map((g) => g.name), [
        'anyscript.lic',
        'bigshot.lic',
        'drscript.lic',
      ]);
    });

    test('sorts by downloads', () async {
      final m = fakeModel();
      await m.refresh();
      m.setSortBy(SortBy.downloads);
      expect(m.visible.first.name, 'bigshot.lic');
      expect(m.visible.last.name, 'jinxonly.lic'); // no count sorts last
    });

    test('one failing source does not block the others', () async {
      final m = fakeModel(jinxFails: true);
      await m.refresh();
      expect(m.stateFor('jinx:extras').state, LoadState.error);
      expect(m.visible, hasLength(3));
    });
  });

  testWidgets('browse, select and show details', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final m = fakeModel();
    final downloads = Downloads(null, autodetect: false);
    await tester.pumpWidget(
      RepoBrowserApp(
        model: m,
        downloads: downloads,
        updates: UpdatesModel(m, downloads),
      ),
    );
    await m.refresh();
    await tester.pumpAndSettle();

    expect(find.text('Select a script to see its details'), findsOneWidget);
    await tester.tap(
      find.textContaining('bigshot.lic', findRichText: true).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Available from'), findsOneWidget);
    expect(find.text('Fake lich'), findsOneWidget);
    expect(find.text('Fake jinx:extras'), findsOneWidget);
    // Jinx header is preferred for the description.
    expect(find.text('Header for bigshot.lic'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing-matches');
    await tester.pumpAndSettle();
    expect(find.text('No matches.'), findsOneWidget);

    // Boolean search reaches the list.
    await tester.enterText(find.byType(TextField), 'bigshot OR drscript');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('drscript.lic', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('anyscript.lic', findRichText: true),
      findsNothing,
    );

    // Installed tab with no Lich folder offers to choose one.
    await tester.tap(find.text('Installed'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Lich folder…'), findsOneWidget);
  });
}
