import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:repo_core/repo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Kept apart from widget tests: TestWidgetsFlutterBinding blocks real HTTP
// (even to this local server) for every test in a file that uses it.

Future<SharedPreferences> freshPrefs() {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  group('custom Jinx repos (local test server)', () {
    late HttpServer server;
    late String url;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = 'http://127.0.0.1:${server.port}/repo';
      server.listen((req) {
        if (req.uri.path == '/repo/manifest.json') {
          req.response.write(
            jsonEncode({
              'available': [
                {'file': '/assets/mine.lic', 'type': 'script', 'tags': []},
              ],
            }),
          );
        } else {
          req.response.statusCode = 404;
        }
        req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    test('URL normalization', () {
      expect(
        CatalogModel.normalizeRepoUrl(' https://x.io/r/manifest.json/ '),
        'https://x.io/r',
      );
      expect(
        CatalogModel.normalizeRepoUrl('https://x.io/r//'),
        'https://x.io/r',
      );
    });

    test('probe, add, persist, remove', () async {
      expect(await CatalogModel.probeJinx('$url/manifest.json'), 1);
      await expectLater(
        CatalogModel.probeJinx('$url/nope'),
        throwsA(isA<RepoException>()),
      );

      final prefs = await freshPrefs();
      final m = CatalogModel(prefs: prefs)..sources.clear(); // offline
      await m.addJinxRepo('mine', '$url/');
      expect(m.allGroups.map((g) => g.name), ['mine.lic']);
      expect(m.isCustom(m.stateFor('jinx:mine')), isTrue);
      expect(() => m.addJinxRepo('mine', url), throwsArgumentError);

      // Restored on the next start (default sources + saved custom ones).
      final again = CatalogModel(prefs: prefs);
      final restored = again.stateFor('jinx:mine');
      expect((restored.source as JinxSource).baseUrl, url);
      expect(again.isCustom(again.stateFor('lich')), isFalse);

      await again.removeSource(restored);
      expect(again.sources.any((s) => s.source.id == 'jinx:mine'), isFalse);
      expect(prefs.getString('customRepos'), '[]');
      expect(
        () => again.removeSource(again.stateFor('lich')),
        throwsStateError,
      );
    });
  });
}
