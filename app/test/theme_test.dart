import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/downloads.dart';
import 'package:lich_repo_browser/main.dart';
import 'package:lich_repo_browser/ui/theme.dart';
import 'package:lich_repo_browser/updates_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Spellbook is the default and the choice is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ThemeController(prefs);
    expect(c.theme, AppTheme.spellbook);
    c.set(AppTheme.light);
    expect(ThemeController(prefs).theme, AppTheme.light);
  });

  test('each theme builds with the expected brightness and extras', () {
    final spell = buildTheme(AppTheme.spellbook);
    expect(spell.colorScheme.brightness, Brightness.dark);
    expect(spell.extension<AppDecor>()!.paper, isNotNull);
    expect(spell.extension<AppDecor>()!.appBarGradient, isNotNull);
    expect(buildTheme(AppTheme.dark).colorScheme.brightness, Brightness.dark);
    expect(buildTheme(AppTheme.light).colorScheme.brightness, Brightness.light);
    expect(buildTheme(AppTheme.light).extension<AppDecor>()!.paper, isNull);
  });

  testWidgets('theme menu switches the app theme', (tester) async {
    final model = CatalogModel(sources: const []);
    final downloads = Downloads(null, autodetect: false);
    final themes = ThemeController(null);
    await tester.pumpWidget(
      RepoBrowserApp(
        model: model,
        downloads: downloads,
        updates: UpdatesModel(model, downloads),
        themes: themes,
      ),
    );
    await tester.pumpAndSettle();
    ColorScheme scheme() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;
    expect(
      scheme().primary,
      buildTheme(AppTheme.spellbook).colorScheme.primary,
    );

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(themes.theme, AppTheme.light);
    expect(scheme().brightness, Brightness.light);
  });
}
