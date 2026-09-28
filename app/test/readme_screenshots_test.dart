// Renders the README screenshots off-screen at a fixed size, with real fonts
// and live catalog data. Skipped unless SCREENSHOTS_OUT is set:
//
//   SCREENSHOTS_OUT=../docs flutter test test/readme_screenshots_test.dart
//
// SCREENSHOTS_THEME=light|dark|spellbook picks a theme (default: the app's).
//
// Uses no Lich folder and no saved settings, so nothing personal appears.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/downloads.dart';
import 'package:lich_repo_browser/main.dart';
import 'package:lich_repo_browser/ui/theme.dart';
import 'package:lich_repo_browser/updates_model.dart';

final _out = Platform.environment['SCREENSHOTS_OUT'];

/// Optional theme name (spellbook, dark, light); defaults to the app default.
final _theme = AppTheme.values
    .where((t) => t.name == Platform.environment['SCREENSHOTS_THEME'])
    .firstOrNull;

/// Real fonts instead of the test font. File reads must happen inside
/// runAsync; the loaders then take already-read bytes.
Future<void> _loadFonts(WidgetTester tester) async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String f) async => (await tester.runAsync(
    () async => (await File(
      f.startsWith('/') ? f : '$dir/$f',
    ).readAsBytes()).buffer.asByteData(),
  ))!;
  // One loader per file: a single loader with several files stalls
  // under the test binding.
  const mono = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf';
  for (final (family, file) in [
    ('Roboto', 'Roboto-Regular.ttf'),
    ('Roboto', 'Roboto-Medium.ttf'),
    ('Roboto', 'Roboto-Bold.ttf'),
    ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    // The description panel asks for 'monospace'.
    if (File(mono).existsSync()) ('monospace', mono),
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(await read(file)));
    await tester.runAsync(loader.load);
  }
}

void main() {
  testWidgets('README screenshots', skip: _out == null, (tester) async {
    // Widget tests block HTTP by default; these screenshots want live data.
    HttpOverrides.global = null;
    await _loadFonts(tester);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final model = CatalogModel();
    final downloads = Downloads(null, autodetect: false);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: RepoBrowserApp(
          model: model,
          downloads: downloads,
          updates: UpdatesModel(model, downloads),
          themes: ThemeController(null)..set(_theme ?? AppTheme.spellbook),
        ),
      ),
    );
    await tester.runAsync(model.refresh);
    await _frames(tester);

    Future<void> shoot(String name) async {
      await _frames(tester);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final img = await render.toImage();
        return img.toByteData(format: ui.ImageByteFormat.png);
      });
      await tester.runAsync(() => Directory(_out!).create(recursive: true));
      await tester.runAsync(
        () => File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List()),
      );
    }

    // 1. Browse: boolean search, list, and bigshot's details.
    model
      ..setSortBy(SortBy.downloads)
      ..setQuery('(tag:hunting OR tag:bounty) downloads:>100');
    final big = model.allGroups.firstWhere((g) => g.name == 'bigshot.lic');
    // Start the details request in real time *before* the UI asks for it;
    // a request begun on the test's fake clock would never complete.
    await tester.runAsync(
      () => model.details(big.entries.firstWhere((e) => e.headerPath != null)),
    );
    model.select(big);
    await _settleReal(tester);
    await shoot('screenshot-browse');

    // 2. Map gallery.
    model
      ..setQuery('')
      ..setGameFilter(GameFilter.gs)
      ..setTypeFilter(TypeFilter.maps)
      ..setSortBy(SortBy.name);
    await tester.pump();
    // Let the visible thumbnails download and decode.
    await _settleReal(tester, rounds: 120);
    await shoot('screenshot-maps');
    model.setTypeFilter(TypeFilter.scripts);
    // Tear down the app so no timers (tooltips, image retries) are left.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}

/// Alternates real waiting (network, image decoding) with frames, so work
/// started by widgets can finish.
Future<void> _settleReal(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps a fixed number of frames. (pumpAndSettle would never return while
/// a loading spinner is animating.)
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
