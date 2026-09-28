import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_model.dart';
import 'debug_capture.dart';
import 'downloads.dart';
import 'ui/browse_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerDebugCapture();
  final prefs = await SharedPreferences.getInstance();
  final model = CatalogModel(prefs: prefs)..refresh();
  runApp(RepoBrowserApp(model: model, downloads: Downloads(prefs)));
}

class RepoBrowserApp extends StatelessWidget {
  const RepoBrowserApp({
    super.key,
    required this.model,
    required this.downloads,
  });

  final CatalogModel model;
  final Downloads downloads;

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
      home: BrowsePage(model: model, downloads: downloads),
    );
  }
}
