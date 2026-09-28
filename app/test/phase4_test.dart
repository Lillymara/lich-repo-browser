import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/downloads.dart';
import 'package:lich_repo_browser/main.dart';
import 'package:lich_repo_browser/updates_model.dart';
import 'package:repo_core/repo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSource implements RepoSource {
  FakeSource(this.id, this.entries);
  @override
  final String id;
  List<CatalogEntry> entries;
  @override
  String get displayName => id;
  @override
  Future<List<CatalogEntry>> fetchCatalog() async => entries;
  @override
  Future<EntryDetails> fetchDetails(CatalogEntry entry) async =>
      EntryDetails(text: '');
  @override
  Future<Uint8List> download(CatalogEntry entry, {String? version}) async =>
      Uint8List(0);
}

CatalogEntry e(String name, {DateTime? updated, String type = 'script'}) =>
    CatalogEntry(
      sourceId: 'jinx:x',
      name: name,
      type: type,
      lastUpdated: updated ?? DateTime(2020),
    );

Future<SharedPreferences> freshPrefs([Map<String, Object> v = const {}]) {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

void main() {
  test('favorites persist and are searchable', () async {
    final prefs = await freshPrefs();
    final m = CatalogModel(
      sources: [
        FakeSource('jinx:x', [e('a.lic'), e('b.lic')]),
      ],
      prefs: prefs,
    );
    await m.refresh();
    m.toggleFavorite(m.allGroups.firstWhere((g) => g.name == 'b.lic'));
    expect(m.countFlag('favorite'), 1);

    m.setShowOnly(ShowOnly.favorites);
    expect(m.visible.map((g) => g.name), ['b.lic']);
    m.setShowOnly(ShowOnly.all);
    m.setQuery('is:fav');
    expect(m.visible.map((g) => g.name), ['b.lic']);

    // A new model with the same prefs remembers it.
    final again = CatalogModel(
      sources: [
        FakeSource('jinx:x', [e('a.lic'), e('b.lic')]),
      ],
      prefs: prefs,
    );
    await again.refresh();
    expect(again.countFlag('favorite'), 1);
  });

  test('new and updated since the last visit', () async {
    final dir = await Directory.systemTemp.createTemp('visit');
    addTearDown(() => dir.delete(recursive: true));
    final prefs = await freshPrefs();
    final source = FakeSource('jinx:x', [
      e('old.lic', updated: DateTime(2020)),
      e('changed.lic', updated: DateTime(2020)),
    ]);

    // First visit: nothing is "new" yet; the visit gets recorded.
    final first = CatalogModel(sources: [source], prefs: prefs, cacheDir: dir);
    await first.loadCached();
    await first.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(first.countFlag('new') + first.countFlag('updated'), 0);

    // Between visits: one script changes, one appears.
    final visit = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt('lastVisitAt')!,
    );
    source.entries = [
      e('old.lic', updated: DateTime(2020)),
      e('changed.lic', updated: visit.add(const Duration(minutes: 1))),
      e('brandnew.lic', updated: visit.add(const Duration(minutes: 1))),
    ];
    final second = CatalogModel(sources: [source], prefs: prefs, cacheDir: dir);
    await second.loadCached();
    await second.refresh();
    String flagsOf(String n) =>
        second.allGroups.firstWhere((g) => g.name == n).flags.join(',');
    expect(flagsOf('brandnew.lic'), 'new');
    expect(flagsOf('changed.lic'), 'updated');
    expect(flagsOf('old.lic'), '');
    second.setShowOnly(ShowOnly.fresh);
    expect(
      second.visible.map((g) => g.name),
      unorderedEquals(['brandnew.lic', 'changed.lic']),
    );

    await second.markAllSeen();
    expect(second.countFlag('new') + second.countFlag('updated'), 0);
  });

  test('installed / outdated flags come from the updates scan', () async {
    final m = CatalogModel(
      sources: [
        FakeSource('jinx:x', [e('a.lic')]),
      ],
    );
    await m.refresh();
    m.setInstalled({'a.lic': true});
    expect(m.allGroups.single.flags, containsAll(['installed', 'outdated']));
    m.setQuery('is:outdated');
    expect(m.visible, hasLength(1));
  });

  testWidgets('star toggles, show-only menu, map gallery', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final m = CatalogModel(
      sources: [
        FakeSource('jinx:x', [
          e('a.lic'),
          e('b.lic'),
          e('town.png', type: 'map'),
        ]),
      ],
    );
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

    await tester.tap(find.byTooltip('Add to favorites').first);
    await tester.pumpAndSettle();
    expect(m.countFlag('favorite'), 1);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites (1)').last);
    await tester.pumpAndSettle();
    expect(m.visible.map((g) => g.name), ['a.lic']);

    m.setShowOnly(ShowOnly.all);
    m.setTypeFilter(TypeFilter.maps);
    await tester.pumpAndSettle();
    expect(find.text('town.png'), findsOneWidget); // gallery tile caption
    expect(find.byType(GridView), findsOneWidget);
  });
}
