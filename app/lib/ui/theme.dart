import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's color themes. Spellbook matches the app icon and is the default.
enum AppTheme {
  spellbook('Spellbook', 'Burgundy, gold, parchment'),
  dark('Dark', 'Plain dark'),
  light('Light', 'Plain light');

  const AppTheme(this.label, this.description);
  final String label;
  final String description;
}

/// Remembers the chosen theme.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    final saved = _prefs?.getString(_key);
    _theme =
        AppTheme.values.where((t) => t.name == saved).firstOrNull ??
        AppTheme.spellbook;
  }

  final SharedPreferences? _prefs;
  static const _key = 'theme';
  late AppTheme _theme;

  AppTheme get theme => _theme;

  void set(AppTheme t) {
    if (t == _theme) return;
    _theme = t;
    _prefs?.setString(_key, t.name);
    notifyListeners();
  }
}

/// Extra theme pieces Material's ColorScheme doesn't cover.
@immutable
class AppDecor extends ThemeExtension<AppDecor> {
  const AppDecor({this.appBarGradient, this.paper, this.ink});

  /// Painted behind the app bar (Spellbook only).
  final Gradient? appBarGradient;

  /// Background and text colors for script descriptions; null means the
  /// normal surface colors.
  final Color? paper;
  final Color? ink;

  static AppDecor of(BuildContext context) =>
      Theme.of(context).extension<AppDecor>() ?? const AppDecor();

  @override
  AppDecor copyWith({Gradient? appBarGradient, Color? paper, Color? ink}) =>
      AppDecor(
        appBarGradient: appBarGradient ?? this.appBarGradient,
        paper: paper ?? this.paper,
        ink: ink ?? this.ink,
      );

  @override
  AppDecor lerp(AppDecor? other, double t) => t < 0.5 ? this : other ?? this;
}

/// Colors taken from the icon (assets/icon/app_icon.svg).
abstract final class _Spellbook {
  static const crimson = Color(0xFF8E1F3A);
  static const wine = Color(0xFF3A0A1C);
  static const gold = Color(0xFFE7B53A);
  static const arcane = Color(0xFF7FE7FF);
  static const arcaneDeep = Color(0xFF1E9BC2);
  static const parchment = Color(0xFFF3E1BC);
  static const parchmentLight = Color(0xFFFFF3D9);
  static const ink = Color(0xFF2B0A14);
}

const _plainSeed = Color(0xFF4A6FA5);

ThemeData buildTheme(AppTheme theme) => switch (theme) {
  AppTheme.spellbook => _spellbook(),
  AppTheme.dark => _plain(Brightness.dark),
  AppTheme.light => _plain(Brightness.light),
};

ThemeData _plain(Brightness b) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _plainSeed, brightness: b),
  extensions: const [AppDecor()],
);

ThemeData _spellbook() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _Spellbook.gold,
    onPrimary: _Spellbook.ink,
    primaryContainer: Color(0xFF6E4B0C),
    onPrimaryContainer: Color(0xFFFFE3A0),
    secondary: _Spellbook.arcane,
    onSecondary: Color(0xFF04262F),
    secondaryContainer: Color(0xFF0E4656),
    onSecondaryContainer: Color(0xFFCBF6FF),
    tertiary: _Spellbook.parchment,
    onTertiary: _Spellbook.wine,
    // Jinx source badges: crimson, so they stand apart from the gold Lich ones.
    tertiaryContainer: Color(0xFF7A1C34),
    onTertiaryContainer: _Spellbook.parchmentLight,
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3A0000),
    surface: Color(0xFF2A0914),
    onSurface: Color(0xFFF6E7C8),
    onSurfaceVariant: Color(0xFFD9BFA0),
    surfaceContainerLowest: Color(0xFF1E060E),
    surfaceContainerLow: Color(0xFF310B18),
    surfaceContainer: Color(0xFF3A0E1D),
    surfaceContainerHigh: Color(0xFF461325),
    surfaceContainerHighest: Color(0xFF53192D),
    outline: Color(0xFFA0706A),
    outlineVariant: Color(0xFF63303B),
    inverseSurface: Color(0xFFF6E7C8),
    onInverseSurface: _Spellbook.wine,
    inversePrimary: _Spellbook.crimson,
    surfaceTint: _Spellbook.gold,
    shadow: Colors.black,
    scrim: Colors.black,
  );
  final base = ThemeData(colorScheme: scheme);
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: _Spellbook.wine,
      foregroundColor: _Spellbook.parchmentLight,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: _Spellbook.gold,
      unselectedLabelColor: _Spellbook.parchment.withValues(alpha: 0.75),
      indicatorColor: _Spellbook.gold,
      dividerColor: Colors.transparent,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF63303B)),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: _Spellbook.arcane,
      thumbColor: _Spellbook.arcane,
      inactiveTrackColor: _Spellbook.arcaneDeep.withValues(alpha: 0.35),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _Spellbook.arcane,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _Spellbook.parchment,
      contentTextStyle: TextStyle(color: _Spellbook.ink),
      actionTextColor: _Spellbook.crimson,
    ),
    extensions: const [
      AppDecor(
        appBarGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Spellbook.crimson, _Spellbook.wine],
        ),
        paper: _Spellbook.parchmentLight,
        ink: _Spellbook.ink,
      ),
    ],
  );
}

/// App-bar button that switches themes.
class ThemeMenuButton extends StatelessWidget {
  const ThemeMenuButton({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppTheme>(
      tooltip: 'Theme',
      icon: const Icon(Icons.palette_outlined),
      initialValue: controller.theme,
      onSelected: controller.set,
      itemBuilder: (_) => [
        for (final t in AppTheme.values)
          PopupMenuItem(
            value: t,
            child: Row(
              children: [
                _Swatch(theme: t),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.label),
                      Text(
                        t.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (t == controller.theme) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check, size: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Three dots previewing a theme's background, accent and highlight.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final s = buildTheme(theme).colorScheme;
    Widget dot(Color c) => Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [dot(s.surface), dot(s.primary), dot(s.secondary)],
    );
  }
}
