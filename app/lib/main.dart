import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_model.dart';
import 'debug_capture.dart';
import 'downloads.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'updates_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final model = CatalogModel(
    prefs: prefs,
    cacheDir: await getApplicationSupportDirectory(),
  );
  // Show the last-known catalogs immediately, then refresh in the background.
  await model.loadCached();
  model.refresh();
  registerDebugCapture(model);
  final downloads = Downloads(prefs);
  runApp(
    RepoBrowserApp(
      model: model,
      downloads: downloads,
      updates: UpdatesModel(model, downloads),
      themes: ThemeController(prefs),
    ),
  );
}

class RepoBrowserApp extends StatelessWidget {
  RepoBrowserApp({
    super.key,
    required this.model,
    required this.downloads,
    required this.updates,
    ThemeController? themes,
  }) : themes = themes ?? ThemeController(null);

  final CatalogModel model;
  final Downloads downloads;
  final UpdatesModel updates;
  final ThemeController themes;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themes,
      builder: (context, _) => MaterialApp(
        title: 'Lich Repo Browser',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(themes.theme),
        home: HomePage(
          catalog: model,
          updates: updates,
          downloads: downloads,
          themes: themes,
        ),
      ),
    );
  }
}
