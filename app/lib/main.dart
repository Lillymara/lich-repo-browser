import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_model.dart';
import 'debug_capture.dart';
import 'downloads.dart';
import 'ui/home_page.dart';
import 'updates_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerDebugCapture();
  final prefs = await SharedPreferences.getInstance();
  final model = CatalogModel(
    prefs: prefs,
    cacheDir: await getApplicationSupportDirectory(),
  );
  // Show the last-known catalogs immediately, then refresh in the background.
  await model.loadCached();
  model.refresh();
  final downloads = Downloads(prefs);
  runApp(
    RepoBrowserApp(
      model: model,
      downloads: downloads,
      updates: UpdatesModel(model, downloads),
    ),
  );
}

class RepoBrowserApp extends StatelessWidget {
  const RepoBrowserApp({
    super.key,
    required this.model,
    required this.downloads,
    required this.updates,
  });

  final CatalogModel model;
  final Downloads downloads;
  final UpdatesModel updates;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4A6FA5),
        brightness: b,
      ),
    );
    return MaterialApp(
      title: 'Lich Repo Browser',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(catalog: model, updates: updates, downloads: downloads),
    );
  }
}
