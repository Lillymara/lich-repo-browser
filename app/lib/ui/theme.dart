import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry in the theme menu.
class ThemeOption {
  const ThemeOption({
    required this.id,
    required this.label,
    required this.description,
    required this.build,
    required this.swatch,
    this.plain = false,
  });

  final String id;
  final String label;
  final String description;
  final ThemeData Function() build;

  /// A few colors to preview the theme in the menu.
  final List<Color> swatch;

  /// Stock Material look rather than one of the themed palettes.
  final bool plain;
}

/// Every theme, in menu order. Leather & Brass is the default.
final List<ThemeOption> themeOptions = [
  for (final p in SpellbookPalettes.all)
    ThemeOption(
      id: p.id,
      label: p.label,
      description: p.description,
      build: () => buildSpellbook(p),
      swatch: [p.headerStart, p.surface, p.primary, p.secondary],
    ),
  for (final b in Brightness.values.reversed)
    ThemeOption(
      id: b == Brightness.dark ? 'dark' : 'light',
      label: b == Brightness.dark ? 'Plain Dark' : 'Plain Light',
      description: 'Standard Material colors',
      build: () => _plain(b),
      swatch: [
        for (final c in [_plain(b).colorScheme]) ...[
          c.surfaceContainer,
          c.surface,
          c.primary,
          c.secondary,
        ],
      ],
      plain: true,
    ),
];

const defaultThemeId = 'leather';

ThemeOption themeById(String? id) =>
    themeOptions.where((t) => t.id == id).firstOrNull ??
    themeOptions.firstWhere((t) => t.id == defaultThemeId);

ThemeData buildTheme(String id) => themeById(id).build();

/// Remembers the chosen theme.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    var saved = _prefs?.getString(_key);
    // v1.1.0 called its single themed option "spellbook"; its successor is
    // the new default.
    if (saved == 'spellbook') saved = defaultThemeId;
    _theme = themeById(saved);
  }

  final SharedPreferences? _prefs;
  static const _key = 'theme';
  late ThemeOption _theme;

  ThemeOption get theme => _theme;

  void set(String id) {
    final t = themeById(id);
    if (t.id == _theme.id) return;
    _theme = t;
    _prefs?.setString(_key, t.id);
    notifyListeners();
  }
}

/// Extra theme pieces Material's ColorScheme doesn't cover.
@immutable
class AppDecor extends ThemeExtension<AppDecor> {
  const AppDecor({this.appBarGradient, this.paper, this.ink});

  /// Painted behind the app bar (themed palettes only).
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

/// The colors a themed palette is built from.
class SpellbookPalette {
  const SpellbookPalette({
    required this.id,
    required this.label,
    required this.description,
    required this.brightness,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.headerStart,
    required this.headerEnd,
    required this.onHeader,
    required this.headerAccent,
    required this.paper,
    required this.ink,
  });

  final String id;
  final String label;
  final String description;
  final Brightness brightness;

  /// Page background and its text.
  final Color surface, onSurface, onSurfaceVariant, outline;

  /// Highlights: selected text, primary buttons, "Lich" badges.
  final Color primary, onPrimary, primaryContainer, onPrimaryContainer;

  /// Selections: chips, segmented buttons, slider.
  final Color secondary, onSecondary, secondaryContainer, onSecondaryContainer;

  /// Jinx source badges.
  final Color tertiaryContainer, onTertiaryContainer;

  /// App bar gradient, its text, and the active tab.
  final Color headerStart, headerEnd, onHeader, headerAccent;

  /// Script description panel.
  final Color paper, ink;

  /// A surface step toward the text color.
  Color _step(double t) => Color.lerp(surface, onSurface, t)!;
}

/// The themed palettes, loosely drawn from the lich/spellbook look of the
/// app icon.
abstract final class SpellbookPalettes {
  static const leather = SpellbookPalette(
    id: 'leather',
    label: 'Leather & Brass',
    description: 'Oxblood, brass and sage',
    brightness: Brightness.dark,
    surface: Color(0xFF1F1B18),
    onSurface: Color(0xFFEDE4D6),
    onSurfaceVariant: Color(0xFFC4B7A6),
    outline: Color(0xFF857767),
    primary: Color(0xFFCDA658),
    onPrimary: Color(0xFF261C0E),
    primaryContainer: Color(0xFF55452A),
    onPrimaryContainer: Color(0xFFF0DDB2),
    secondary: Color(0xFFA9C2A6),
    onSecondary: Color(0xFF1B2A1B),
    secondaryContainer: Color(0xFF3A4A3A),
    onSecondaryContainer: Color(0xFFDCEAD8),
    tertiaryContainer: Color(0xFF5C2A2C),
    onTertiaryContainer: Color(0xFFF2E3D8),
    headerStart: Color(0xFF6A2B2F),
    headerEnd: Color(0xFF2A201C),
    onHeader: Color(0xFFF2E8D8),
    headerAccent: Color(0xFFCDA658),
    paper: Color(0xFFEFE6D3),
    ink: Color(0xFF2A211A),
  );

  static const midnight = SpellbookPalette(
    id: 'midnight',
    label: 'Midnight Grimoire',
    description: 'Blue-black with a burgundy header',
    brightness: Brightness.dark,
    surface: Color(0xFF17161D),
    onSurface: Color(0xFFE9E5DD),
    onSurfaceVariant: Color(0xFFBDB7AD),
    outline: Color(0xFF7C7684),
    primary: Color(0xFFD9B35F),
    onPrimary: Color(0xFF221A0B),
    primaryContainer: Color(0xFF4F4225),
    onPrimaryContainer: Color(0xFFF1DDAF),
    secondary: Color(0xFF86CCD8),
    onSecondary: Color(0xFF0D2A30),
    secondaryContainer: Color(0xFF26414A),
    onSecondaryContainer: Color(0xFFCDEBF0),
    tertiaryContainer: Color(0xFF5A2437),
    onTertiaryContainer: Color(0xFFF0E1E6),
    headerStart: Color(0xFF5B1F33),
    headerEnd: Color(0xFF1E1B26),
    onHeader: Color(0xFFF1EBE0),
    headerAccent: Color(0xFFD9B35F),
    paper: Color(0xFFF1EADC),
    ink: Color(0xFF22202A),
  );

  static const muted = SpellbookPalette(
    id: 'muted',
    label: 'Muted Spellbook',
    description: 'Dusty wine, soft gold and teal',
    brightness: Brightness.dark,
    surface: Color(0xFF241519),
    onSurface: Color(0xFFEDE3D3),
    onSurfaceVariant: Color(0xFFC7B6A4),
    outline: Color(0xFF8A7471),
    primary: Color(0xFFD6B26A),
    onPrimary: Color(0xFF2A1A12),
    primaryContainer: Color(0xFF5A4726),
    onPrimaryContainer: Color(0xFFF2DDB0),
    secondary: Color(0xFF93C9CF),
    onSecondary: Color(0xFF10292C),
    secondaryContainer: Color(0xFF2C4448),
    onSecondaryContainer: Color(0xFFCFE8EA),
    tertiaryContainer: Color(0xFF5E2E3A),
    onTertiaryContainer: Color(0xFFF1E4D8),
    headerStart: Color(0xFF5E2636),
    headerEnd: Color(0xFF2E1A20),
    onHeader: Color(0xFFF3E9DA),
    headerAccent: Color(0xFFD6B26A),
    paper: Color(0xFFF4ECDF),
    ink: Color(0xFF2E1D22),
  );

  static const vivid = SpellbookPalette(
    id: 'vivid',
    label: 'Vivid Spellbook',
    description: "The icon's full-strength colors",
    brightness: Brightness.dark,
    surface: Color(0xFF2A0914),
    onSurface: Color(0xFFF6E7C8),
    onSurfaceVariant: Color(0xFFD9BFA0),
    outline: Color(0xFFA0706A),
    primary: Color(0xFFE7B53A),
    onPrimary: Color(0xFF2B0A14),
    primaryContainer: Color(0xFF6E4B0C),
    onPrimaryContainer: Color(0xFFFFE3A0),
    secondary: Color(0xFF7FE7FF),
    onSecondary: Color(0xFF04262F),
    secondaryContainer: Color(0xFF0E4656),
    onSecondaryContainer: Color(0xFFCBF6FF),
    tertiaryContainer: Color(0xFF7A1C34),
    onTertiaryContainer: Color(0xFFFFF3D9),
    headerStart: Color(0xFF8E1F3A),
    headerEnd: Color(0xFF3A0A1C),
    onHeader: Color(0xFFFFF3D9),
    headerAccent: Color(0xFFE7B53A),
    paper: Color(0xFFFFF3D9),
    ink: Color(0xFF2B0A14),
  );

  static const phylactery = SpellbookPalette(
    id: 'phylactery',
    label: 'Phylactery',
    description: 'Emerald and silver',
    brightness: Brightness.dark,
    surface: Color(0xFF121A17),
    onSurface: Color(0xFFE4ECE7),
    onSurfaceVariant: Color(0xFFAFC0B6),
    outline: Color(0xFF6E8279),
    primary: Color(0xFF4FD39A),
    onPrimary: Color(0xFF06281A),
    primaryContainer: Color(0xFF1D4A36),
    onPrimaryContainer: Color(0xFFB8F2D5),
    secondary: Color(0xFFC3CCD6),
    onSecondary: Color(0xFF1E252C),
    secondaryContainer: Color(0xFF37414B),
    onSecondaryContainer: Color(0xFFE1E7EE),
    tertiaryContainer: Color(0xFF3A4A5E),
    onTertiaryContainer: Color(0xFFE3EAF2),
    headerStart: Color(0xFF1F5A43),
    headerEnd: Color(0xFF111916),
    onHeader: Color(0xFFEAF5EF),
    headerAccent: Color(0xFF7CF0BC),
    paper: Color(0xFFEEF3EF),
    ink: Color(0xFF16221C),
  );

  static const frost = SpellbookPalette(
    id: 'frost',
    label: 'Frostbound',
    description: 'Ice blue and pale violet',
    brightness: Brightness.dark,
    surface: Color(0xFF121821),
    onSurface: Color(0xFFE6EEF6),
    onSurfaceVariant: Color(0xFFAEBBCB),
    outline: Color(0xFF6F7E91),
    primary: Color(0xFF9FD8FF),
    onPrimary: Color(0xFF0B2536),
    primaryContainer: Color(0xFF274A63),
    onPrimaryContainer: Color(0xFFD2ECFF),
    secondary: Color(0xFF8EE3EF),
    onSecondary: Color(0xFF0A2A30),
    secondaryContainer: Color(0xFF22474F),
    onSecondaryContainer: Color(0xFFCDEFF4),
    tertiaryContainer: Color(0xFF4B3A63),
    onTertiaryContainer: Color(0xFFEDE4FF),
    headerStart: Color(0xFF2B4A6E),
    headerEnd: Color(0xFF131A24),
    onHeader: Color(0xFFEEF5FC),
    headerAccent: Color(0xFF9FD8FF),
    paper: Color(0xFFF1F5FA),
    ink: Color(0xFF16202C),
  );

  static const ashen = SpellbookPalette(
    id: 'ashen',
    label: 'Ashen Bone',
    description: 'Neutral greys and bone white',
    brightness: Brightness.dark,
    surface: Color(0xFF1A1918),
    onSurface: Color(0xFFE8E4DC),
    onSurfaceVariant: Color(0xFFB9B3A9),
    outline: Color(0xFF7A756D),
    primary: Color(0xFFE3D5B8),
    onPrimary: Color(0xFF2A2519),
    primaryContainer: Color(0xFF4A4436),
    onPrimaryContainer: Color(0xFFF1E7D2),
    secondary: Color(0xFFA7B4C2),
    onSecondary: Color(0xFF1C242C),
    secondaryContainer: Color(0xFF37404A),
    onSecondaryContainer: Color(0xFFDCE4EC),
    tertiaryContainer: Color(0xFF4D3B3B),
    onTertiaryContainer: Color(0xFFF0E2E0),
    headerStart: Color(0xFF3A3835),
    headerEnd: Color(0xFF1C1B1A),
    onHeader: Color(0xFFEDE9E2),
    headerAccent: Color(0xFFE3D5B8),
    paper: Color(0xFFEFEBE3),
    ink: Color(0xFF22201D),
  );

  static const ember = SpellbookPalette(
    id: 'ember',
    label: 'Ember',
    description: 'Charcoal and glowing orange',
    brightness: Brightness.dark,
    surface: Color(0xFF1C1512),
    onSurface: Color(0xFFF0E3D8),
    onSurfaceVariant: Color(0xFFC6B09F),
    outline: Color(0xFF8A7263),
    primary: Color(0xFFF29A52),
    onPrimary: Color(0xFF2E1405),
    primaryContainer: Color(0xFF5E3219),
    onPrimaryContainer: Color(0xFFFFD9BD),
    secondary: Color(0xFFF2C66B),
    onSecondary: Color(0xFF2E2206),
    secondaryContainer: Color(0xFF4F3F16),
    onSecondaryContainer: Color(0xFFFBE6B5),
    tertiaryContainer: Color(0xFF5A2323),
    onTertiaryContainer: Color(0xFFF6DEDA),
    headerStart: Color(0xFF7A2E14),
    headerEnd: Color(0xFF22150F),
    onHeader: Color(0xFFFBEBDD),
    headerAccent: Color(0xFFF29A52),
    paper: Color(0xFFF8EEE3),
    ink: Color(0xFF2A1A12),
  );

  static const parchment = SpellbookPalette(
    id: 'parchment',
    label: 'Parchment',
    description: 'Light cream with burgundy',
    brightness: Brightness.light,
    surface: Color(0xFFF7F0E3),
    onSurface: Color(0xFF2E1A1F),
    onSurfaceVariant: Color(0xFF5E4A45),
    outline: Color(0xFF9C8A7C),
    primary: Color(0xFF7E2238),
    onPrimary: Color(0xFFFFF6EC),
    primaryContainer: Color(0xFFF0D9A6),
    onPrimaryContainer: Color(0xFF4A3510),
    secondary: Color(0xFF1C7C8C),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCFE7E9),
    onSecondaryContainer: Color(0xFF0E3C44),
    tertiaryContainer: Color(0xFFF2D3D9),
    onTertiaryContainer: Color(0xFF5E1A2B),
    headerStart: Color(0xFF7E2238),
    headerEnd: Color(0xFF4A1424),
    onHeader: Color(0xFFFFF4E6),
    headerAccent: Color(0xFFF0C766),
    paper: Color(0xFFFFFBF3),
    ink: Color(0xFF2E1A1F),
  );

  static const all = [
    leather,
    midnight,
    muted,
    vivid,
    phylactery,
    frost,
    ashen,
    ember,
    parchment,
  ];
}

const _plainSeed = Color(0xFF4A6FA5);

ThemeData _plain(Brightness b) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _plainSeed, brightness: b),
  extensions: const [AppDecor()],
);

ThemeData buildSpellbook(SpellbookPalette p) {
  final dark = p.brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    secondaryContainer: p.secondaryContainer,
    onSecondaryContainer: p.onSecondaryContainer,
    tertiary: p.paper,
    onTertiary: p.ink,
    tertiaryContainer: p.tertiaryContainer,
    onTertiaryContainer: p.onTertiaryContainer,
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
    onError: dark ? const Color(0xFF3A0000) : Colors.white,
    surface: p.surface,
    onSurface: p.onSurface,
    onSurfaceVariant: p.onSurfaceVariant,
    // Containers step from the page color toward the text color.
    surfaceContainerLowest: Color.lerp(
      p.surface,
      dark ? Colors.black : Colors.white,
      0.3,
    )!,
    surfaceContainerLow: p._step(0.03),
    surfaceContainer: p._step(0.06),
    surfaceContainerHigh: p._step(0.09),
    surfaceContainerHighest: p._step(0.13),
    outline: p.outline,
    outlineVariant: p._step(0.22),
    inverseSurface: p.onSurface,
    onInverseSurface: p.surface,
    inversePrimary: p.headerStart,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
    scrim: Colors.black,
  );
  final base = ThemeData(colorScheme: scheme);
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.headerEnd,
      foregroundColor: p.onHeader,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: p.headerAccent,
      unselectedLabelColor: p.onHeader.withValues(alpha: 0.75),
      indicatorColor: p.headerAccent,
      dividerColor: Colors.transparent,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: p.secondary,
      thumbColor: p.secondary,
      inactiveTrackColor: p.secondary.withValues(alpha: 0.3),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.secondary),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? p.paper : p.ink,
      contentTextStyle: TextStyle(color: dark ? p.ink : p.paper),
      actionTextColor: p.headerStart,
    ),
    extensions: [
      AppDecor(
        appBarGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.headerStart, p.headerEnd],
        ),
        paper: p.paper,
        ink: p.ink,
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
    final small = Theme.of(context).textTheme.bodySmall;
    PopupMenuEntry<String> item(ThemeOption t) => PopupMenuItem(
      value: t.id,
      child: Row(
        children: [
          _Swatch(colors: t.swatch),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.label),
                Text(t.description, style: small),
              ],
            ),
          ),
          if (t.id == controller.theme.id) ...[
            const SizedBox(width: 12),
            const Icon(Icons.check, size: 18),
          ],
        ],
      ),
    );
    PopupMenuEntry<String> heading(String text) => PopupMenuItem(
      enabled: false,
      height: 32,
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
    return PopupMenuButton<String>(
      tooltip: 'Theme',
      icon: const Icon(Icons.palette_outlined),
      initialValue: controller.theme.id,
      onSelected: controller.set,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
      itemBuilder: (_) => [
        heading('Themed'),
        for (final t in themeOptions.where((t) => !t.plain)) item(t),
        const PopupMenuDivider(),
        heading('Plain'),
        for (final t in themeOptions.where((t) => t.plain)) item(t),
      ],
    );
  }
}

/// Dots previewing a theme's header, page, highlight and accent colors.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
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
      children: [for (final c in colors) dot(c)],
    );
  }
}
