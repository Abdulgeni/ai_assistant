import 'package:flutter/material.dart';

/// Arabic-first type system.
///
/// Rules baked in:
///  * IBM Plex Sans Arabic (OFL), bundled as an asset (see pubspec).
///  * Every role has line height >= 1.5 (Arabic needs the room).
///  * letterSpacing is ALWAYS 0: spacing breaks Arabic letter joining.
///  * Even leading distribution keeps tall Arabic lines visually centered.
abstract final class AppTypography {
  static const String family = 'IBMPlexSansArabic';

  /// Fallbacks for glyphs the bundled font lacks. Unknown names are ignored.
  static const List<String> fallback = <String>[
    'Noto Sans Arabic',
    'SF Arabic',
    'Roboto',
  ];

  static const String codeFamily = 'monospace';
  static const List<String> codeFallback = <String>[
    'Menlo',
    'Roboto Mono',
    'Courier New',
  ];

  static TextStyle _style(
    double size,
    FontWeight weight, {
    double height = 1.5,
  }) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: 0,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Colorless text theme; [AppTheme] applies palette colors.
  static TextTheme textTheme() => TextTheme(
        displayLarge: _style(40, FontWeight.w700),
        displayMedium: _style(34, FontWeight.w700),
        displaySmall: _style(30, FontWeight.w700),
        headlineLarge: _style(28, FontWeight.w600),
        headlineMedium: _style(26, FontWeight.w600),
        headlineSmall: _style(24, FontWeight.w600),
        titleLarge: _style(20, FontWeight.w600),
        titleMedium: _style(16, FontWeight.w600),
        titleSmall: _style(14, FontWeight.w600),
        bodyLarge: _style(16, FontWeight.w400, height: 1.6),
        bodyMedium: _style(14, FontWeight.w400, height: 1.6),
        bodySmall: _style(12, FontWeight.w400),
        labelLarge: _style(14, FontWeight.w600),
        labelMedium: _style(12, FontWeight.w600),
        labelSmall: _style(12, FontWeight.w500),
      );

  /// Code blocks. Code is LTR content; callers wrap it in an LTR Directionality.
  static TextStyle code({Color? color}) => TextStyle(
        fontFamily: codeFamily,
        fontFamilyFallback: codeFallback,
        fontSize: 13,
        height: 1.5,
        letterSpacing: 0,
        color: color,
      );
}
