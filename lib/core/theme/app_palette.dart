import 'package:flutter/material.dart';

/// All app colors for one brightness. Registered as a [ThemeExtension], so
/// widgets read `context.palette` and never hardcode a color.
///
/// Contrast is enforced by `test/unit/theme/app_palette_test.dart`:
/// text on surfaces >= 4.5:1 (primary >= 7:1), strong outline >= 3:1.
/// Glass tokens are translucent and are NOT contrast-tested; never place text
/// on glass unless the backdrop is known.
final class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.surfaceRaised,
    required this.glassFill,
    required this.glassBorder,
    required this.outline,
    required this.outlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.userBubbleStart,
    required this.userBubbleEnd,
    required this.onUserBubble,
    required this.assistantBubble,
    required this.onAssistantBubble,
    required this.codeBackground,
    required this.onCode,
    required this.success,
    required this.warning,
    required this.danger,
    required this.orbA,
    required this.orbB,
    required this.orbC,
  });

  /// "Midnight teal" dark theme.
  static const AppPalette dark = AppPalette(
    background: Color(0xFF0A1012),
    backgroundAlt: Color(0xFF101A24),
    surface: Color(0xFF111B1F),
    surfaceRaised: Color(0xFF18262B),
    glassFill: Color(0x14FFFFFF),
    glassBorder: Color(0x24FFFFFF),
    outline: Color(0xFF2A3A40),
    outlineStrong: Color(0xFF6B8088),
    textPrimary: Color(0xFFEAF3F2),
    textSecondary: Color(0xFFA9BDBD),
    textTertiary: Color(0xFF8EA3A3),
    accent: Color(0xFF4FD1C5),
    onAccent: Color(0xFF04211F),
    accentContainer: Color(0xFF12403D),
    onAccentContainer: Color(0xFFB8F3EC),
    userBubbleStart: Color(0xFF0F766E),
    userBubbleEnd: Color(0xFF4338CA),
    onUserBubble: Color(0xFFFFFFFF),
    assistantBubble: Color(0xFF18262B),
    onAssistantBubble: Color(0xFFEAF3F2),
    codeBackground: Color(0xFF0D1518),
    onCode: Color(0xFFD6E7E5),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFF8A80),
    orbA: Color(0xFF2DD4BF),
    orbB: Color(0xFF6366F1),
    orbC: Color(0xFFC084FC),
  );

  /// "Porcelain teal" light theme.
  static const AppPalette light = AppPalette(
    background: Color(0xFFF6FAF9),
    backgroundAlt: Color(0xFFE9F3F2),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF5F4),
    glassFill: Color(0xB3FFFFFF),
    glassBorder: Color(0x290B1F1E),
    outline: Color(0xFFD3E0DE),
    outlineStrong: Color(0xFF6E8583),
    textPrimary: Color(0xFF0B1F1E),
    textSecondary: Color(0xFF42605E),
    textTertiary: Color(0xFF527270),
    accent: Color(0xFF0F766E),
    onAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFCDEFEA),
    onAccentContainer: Color(0xFF073B37),
    userBubbleStart: Color(0xFF0F766E),
    userBubbleEnd: Color(0xFF4338CA),
    onUserBubble: Color(0xFFFFFFFF),
    assistantBubble: Color(0xFFFFFFFF),
    onAssistantBubble: Color(0xFF0B1F1E),
    codeBackground: Color(0xFFEAF1F0),
    onCode: Color(0xFF12312F),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    danger: Color(0xFFB3261E),
    orbA: Color(0xFF14B8A6),
    orbB: Color(0xFF6366F1),
    orbC: Color(0xFFA855F7),
  );

  // Page
  final Color background;
  final Color backgroundAlt;

  // Surfaces
  final Color surface;
  final Color surfaceRaised;
  final Color glassFill;
  final Color glassBorder;

  /// Decorative divider/border. NOT for identifying controls.
  final Color outline;

  /// Control borders and focus indicators (>= 3:1 on surfaces).
  final Color outlineStrong;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Accent
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;

  // Chat
  final Color userBubbleStart;
  final Color userBubbleEnd;
  final Color onUserBubble;
  final Color assistantBubble;
  final Color onAssistantBubble;
  final Color codeBackground;
  final Color onCode;

  // Status
  final Color success;
  final Color warning;
  final Color danger;

  // Voice orb
  final Color orbA;
  final Color orbB;
  final Color orbC;

  /// Directional, so the gradient mirrors in RTL.
  LinearGradient get userBubbleGradient => LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: <Color>[userBubbleStart, userBubbleEnd],
      );

  /// Subtle full-screen backdrop.
  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[background, backgroundAlt],
      );

  List<Color> get orbColors => <Color>[orbA, orbB, orbC];

  /// Every color, in declaration order. Used by tests to check [copyWith] and
  /// [lerp] cover every field.
  List<Color> get colors => <Color>[
        background,
        backgroundAlt,
        surface,
        surfaceRaised,
        glassFill,
        glassBorder,
        outline,
        outlineStrong,
        textPrimary,
        textSecondary,
        textTertiary,
        accent,
        onAccent,
        accentContainer,
        onAccentContainer,
        userBubbleStart,
        userBubbleEnd,
        onUserBubble,
        assistantBubble,
        onAssistantBubble,
        codeBackground,
        onCode,
        success,
        warning,
        danger,
        orbA,
        orbB,
        orbC,
      ];

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundAlt,
    Color? surface,
    Color? surfaceRaised,
    Color? glassFill,
    Color? glassBorder,
    Color? outline,
    Color? outlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? userBubbleStart,
    Color? userBubbleEnd,
    Color? onUserBubble,
    Color? assistantBubble,
    Color? onAssistantBubble,
    Color? codeBackground,
    Color? onCode,
    Color? success,
    Color? warning,
    Color? danger,
    Color? orbA,
    Color? orbB,
    Color? orbC,
  }) =>
      AppPalette(
        background: background ?? this.background,
        backgroundAlt: backgroundAlt ?? this.backgroundAlt,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        glassFill: glassFill ?? this.glassFill,
        glassBorder: glassBorder ?? this.glassBorder,
        outline: outline ?? this.outline,
        outlineStrong: outlineStrong ?? this.outlineStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentContainer: accentContainer ?? this.accentContainer,
        onAccentContainer: onAccentContainer ?? this.onAccentContainer,
        userBubbleStart: userBubbleStart ?? this.userBubbleStart,
        userBubbleEnd: userBubbleEnd ?? this.userBubbleEnd,
        onUserBubble: onUserBubble ?? this.onUserBubble,
        assistantBubble: assistantBubble ?? this.assistantBubble,
        onAssistantBubble: onAssistantBubble ?? this.onAssistantBubble,
        codeBackground: codeBackground ?? this.codeBackground,
        onCode: onCode ?? this.onCode,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        orbA: orbA ?? this.orbA,
        orbB: orbB ?? this.orbB,
        orbC: orbC ?? this.orbC,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      backgroundAlt: l(backgroundAlt, other.backgroundAlt),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      glassFill: l(glassFill, other.glassFill),
      glassBorder: l(glassBorder, other.glassBorder),
      outline: l(outline, other.outline),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentContainer: l(accentContainer, other.accentContainer),
      onAccentContainer: l(onAccentContainer, other.onAccentContainer),
      userBubbleStart: l(userBubbleStart, other.userBubbleStart),
      userBubbleEnd: l(userBubbleEnd, other.userBubbleEnd),
      onUserBubble: l(onUserBubble, other.onUserBubble),
      assistantBubble: l(assistantBubble, other.assistantBubble),
      onAssistantBubble: l(onAssistantBubble, other.onAssistantBubble),
      codeBackground: l(codeBackground, other.codeBackground),
      onCode: l(onCode, other.onCode),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      orbA: l(orbA, other.orbA),
      orbB: l(orbB, other.orbB),
      orbC: l(orbC, other.orbC),
    );
  }
}
