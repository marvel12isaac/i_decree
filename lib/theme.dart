import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens.
///
/// Direction: calm and quiet, so the words are the focus. Cool stone
/// background, deep navy for actions, and one warm gold reserved for the
/// streak (the single bold element). Quotes are set in a serif (Lora); the
/// interface uses DM Sans.
class Palette {
  static const paper = Color(0xFFF2F4F3);
  static const ink = Color(0xFF16202E);
  static const deep = Color(0xFF23395B);
  static const paleDeep = Color(0x1F23395B); // deep at ~12% opacity
  static const gold = Color(0xFFC98F0A);
  static const sage = Color(0xFF2E7D6B);
  static const muted = Color(0xFF66727F);
  static const line = Color(0xFFD5DBD8);
  static const danger = Color(0xFFB3402E);
}

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

  const scheme = ColorScheme.light(
    primary: Palette.deep,
    onPrimary: Colors.white,
    secondary: Palette.sage,
    onSecondary: Colors.white,
    surface: Palette.paper,
    onSurface: Palette.ink,
    error: Palette.danger,
    outline: Palette.line,
  );

  final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme)
      .apply(bodyColor: Palette.ink, displayColor: Palette.ink);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    textTheme: textTheme,
    extensions: const [AppColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.paper,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.dmSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Palette.ink,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Palette.line,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Serif style for declaration text.
TextStyle quoteStyle({double size = 22, Color? color}) =>
    GoogleFonts.lora(fontSize: size, height: 1.55, color: color);


@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.iconBg,
    required this.iconFg,
    required this.teal,
    required this.onTeal,
    required this.blue,
    required this.ring,
    required this.pill,
    required this.flame,
    required this.overdue,
  });

  final Color background, surface, text, muted, line, iconBg, iconFg;
  final Color teal, onTeal, blue, ring, pill, flame;
  final Color overdue;

  static const light = AppColors(
    background: Palette.paper,
    surface: Color(0xFFFFFFFF),
    text: Palette.ink,
    muted: Palette.muted,
    line: Palette.line,
    iconBg: Palette.paleDeep,
    iconFg: Palette.deep,
    teal: Color(0xFF1F9E8F),
    onTeal: Color(0xFFFFFFFF),
    blue: Color(0xFF3F8FD8),
    ring: Color(0xFFB4BEC6),
    pill: Color(0xFF2F7FD8),
    flame: Color(0xFFF28C28),
    overdue: Color(0xFFC85A41),
    
  );

  static const dark = AppColors(
    background: Color(0xFF0E151D),
    surface: Color(0xFF17212C),
    text: Color(0xFFE8EDF2),
    muted: Color(0xFF93A0AD),
    line: Color(0xFF2B3744),
    iconBg: Color(0x2E3CC4B2),
    iconFg: Color(0xFF7FD9CC),
    teal: Color(0xFF3CC4B2),
    onTeal: Color(0xFF06221E),
    blue: Color(0xFF6CB4F5),
    ring: Color(0xFF4A5866),
    pill: Color(0xFF1F8F81),
    flame: Color(0xFFFFA033),    
    overdue: Color(0xFFE2725B),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.light;

  @override
  AppColors copyWith({
    Color? background, Color? surface, Color? text, Color? muted,
    Color? line, Color? iconBg, Color? iconFg, Color? teal, Color? onTeal,
    Color? blue, Color? ring, Color? pill, Color? flame, Color? overdue,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        iconBg: iconBg ?? this.iconBg,
        iconFg: iconFg ?? this.iconFg,
        teal: teal ?? this.teal,
        onTeal: onTeal ?? this.onTeal,
        blue: blue ?? this.blue,
        ring: ring ?? this.ring,
        pill: pill ?? this.pill,
        flame: flame ?? this.flame,
        overdue: overdue ?? this.overdue,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      iconBg: l(iconBg, other.iconBg),
      iconFg: l(iconFg, other.iconFg),
      teal: l(teal, other.teal),
      onTeal: l(onTeal, other.onTeal),
      blue: l(blue, other.blue),
      ring: l(ring, other.ring),
      pill: l(pill, other.pill),
      flame: l(flame, other.flame),
      overdue: l(overdue, other.overdue),
    );
  }
}

ThemeData buildDarkTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
  const c = AppColors.dark;

  final scheme = ColorScheme.dark(
    primary: c.teal,
    onPrimary: c.onTeal,
    secondary: c.blue,
    onSecondary: c.onTeal,
    surface: c.background,
    onSurface: c.text,
    error: const Color(0xFFE57B6A),
    outline: c.line,
  );

  final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme)
      .apply(bodyColor: c.text, displayColor: c.text);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.dmSans(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: c.text,
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    extensions: const [AppColors.dark],
  );
}