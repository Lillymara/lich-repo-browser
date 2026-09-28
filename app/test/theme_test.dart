import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lich_repo_browser/catalog_model.dart';
import 'package:lich_repo_browser/downloads.dart';
import 'package:lich_repo_browser/main.dart';
import 'package:lich_repo_browser/ui/theme.dart';
import 'package:lich_repo_browser/updates_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Leather & Brass is the default and the choice is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ThemeController(prefs);
    expect(c.theme.id, 'leather');
    c.set('frost');
    expect(ThemeController(prefs).theme.id, 'frost');
    c.set('no-such-theme');
    expect(ThemeController(prefs).theme.id, 'leather');
  });

  test("v1.1.0's 'spellbook' setting maps to the new default", () async {
    SharedPreferences.setMockInitialValues({'theme': 'spellbook'});
    final prefs = await SharedPreferences.getInstance();
    expect(ThemeController(prefs).theme.id, defaultThemeId);
  });

  test('every theme builds, with unique ids and the right extras', () {
    final ids = themeOptions.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids,
      containsAll(['leather', 'vivid', 'parchment', 'dark', 'light']),
    );
    for (final t in themeOptions) {
      final theme = t.build();
      final decor = theme.extension<AppDecor>()!;
      expect(decor.paper == null, t.plain, reason: t.id);
      expect(decor.appBarGradient == null, t.plain, reason: t.id);
    }
    expect(buildTheme('parchment').colorScheme.brightness, Brightness.light);
    expect(buildTheme('light').colorScheme.brightness, Brightness.light);
    expect(buildTheme('ember').colorScheme.brightness, Brightness.dark);
  });

  test('themed palettes keep text readable (WCAG AA 4.5:1)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final p in SpellbookPalettes.all) {
      final pairs = {
        'text on page': (p.onSurface, p.surface),
        'muted text on page': (p.onSurfaceVariant, p.surface),
        'highlight on page': (p.primary, p.surface),
        'button text': (p.onPrimary, p.primary),
        'Lich badge': (p.onPrimaryContainer, p.primaryContainer),
        'Jinx badge': (p.onTertiaryContainer, p.tertiaryContainer),
        'selection': (p.onSecondaryContainer, p.secondaryContainer),
        'header text': (p.onHeader, p.headerEnd),
        'description': (p.ink, p.paper),
      };
      for (final MapEntry(key: what, value: (fg, bg)) in pairs.entries) {
        expect(
          contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '${p.id}: $what',
        );
      }
    }
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
    expect(scheme().primary, buildTheme('leather').colorScheme.primary);

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('Themed'), findsOneWidget);
    await tester.tap(find.text('Plain Light'));
    await tester.pumpAndSettle();
    expect(themes.theme.id, 'light');
    expect(scheme().brightness, Brightness.light);
  });
}
