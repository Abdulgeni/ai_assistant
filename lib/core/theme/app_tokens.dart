import 'package:flutter/material.dart';

/// Spacing scale (logical pixels). The only source of padding and gap values.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii. Bubbles use [lg] with an [xs] "tail" corner.
abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// Component and layout sizes.
abstract final class AppSizes {
  /// Minimum interactive target (accessibility guideline).
  static const double minTouchTarget = 48;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double composerMinHeight = 56;

  /// Readable column width on tablets and landscape.
  static const double contentMaxWidth = 720;

  /// Max bubble width as a fraction of the available width.
  static const double bubbleMaxWidthFraction = 0.85;
}

/// Motion durations. UI transitions stay within 150 to 350 ms.
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);

  /// Cross-fade used instead of movement when reduce-motion is on.
  static const Duration reducedFade = Duration(milliseconds: 100);

  /// Ambient loops (voice orb breathing). Disabled under reduce-motion.
  static const Duration ambient = Duration(milliseconds: 2400);

  /// Streaming caret blink period.
  static const Duration caretBlink = Duration(milliseconds: 530);
}

/// Motion curves, used consistently across the app.
abstract final class AppCurves {
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve exit = Curves.easeInCubic;
}

/// Reduce-motion aware access to motion tokens.
///
/// Movement durations collapse to zero when the OS "reduce motion" setting is
/// on; [fade] provides a short cross-fade instead, and ambient loops must be
/// gated on [allowAmbientLoops].
final class AppMotion {
  const AppMotion({required this.reduceMotion});

  factory AppMotion.of(BuildContext context) =>
      AppMotion(reduceMotion: MediaQuery.disableAnimationsOf(context));

  final bool reduceMotion;

  Duration get fast => _movement(AppDurations.fast);
  Duration get normal => _movement(AppDurations.normal);
  Duration get slow => _movement(AppDurations.slow);

  /// Duration for opacity-only transitions.
  Duration get fade =>
      reduceMotion ? AppDurations.reducedFade : AppDurations.normal;

  bool get allowAmbientLoops => !reduceMotion;

  Duration get ambient => AppDurations.ambient;
  Duration get caretBlink => AppDurations.caretBlink;

  Curve get standard => AppCurves.standard;
  Curve get emphasized => AppCurves.emphasized;
  Curve get exit => AppCurves.exit;

  Duration _movement(Duration d) => reduceMotion ? Duration.zero : d;
}

/// Shadow recipes. Offsets are vertical only, so they never need mirroring.
abstract final class AppShadows {
  static List<BoxShadow> soft(Color tint) => <BoxShadow>[
        BoxShadow(
          color: tint.withValues(alpha: 0.10),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> medium(Color tint) => <BoxShadow>[
        BoxShadow(
          color: tint.withValues(alpha: 0.14),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// Colored halo for the voice orb and focused accents.
  static List<BoxShadow> glow(Color color) => <BoxShadow>[
        BoxShadow(
          color: color.withValues(alpha: 0.35),
          blurRadius: 32,
          spreadRadius: 2,
        ),
      ];
}

/// Blur strengths for glass surfaces.
abstract final class AppBlur {
  static const double soft = 12;
  static const double strong = 24;
}

/// Interaction feedback values.
abstract final class AppInteraction {
  static const double pressedScale = 0.96;
  static const double reducedMotionPressedOpacity = 0.7;
  static const double disabledOpacity = 0.38;
  static const double focusRingWidth = 2;
}

/// Decorative backdrop glow values.
abstract final class AppBackdrop {
  /// Glow diameter as a multiple of the screen's shortest side.
  static const double glowDiameterFactor = 1.2;

  /// How far the glow hangs off the screen edge, as a fraction of its size.
  static const double glowOverhang = 0.35;
  static const double glowAlpha = 0.16;
}

/// Skeleton loader values.
abstract final class AppSkeleton {
  static const double lineHeight = 12;
  static const double lineGap = 8;
  static const double lastLineWidthFraction = 0.6;
}

/// Chat screen values.
abstract final class AppChat {
  /// Assistant bubbles may be wider than user bubbles (long answers, code).
  static const double assistantBubbleMaxWidthFraction = 0.95;

  /// Distance from the newest message (px) within which the list counts as
  /// "following" new content.
  static const double pinThreshold = 48;

  /// Distance from the oldest loaded message (px) at which the next page of
  /// history is requested.
  static const double loadOlderThreshold = 400;

  static const double entranceSlide = 12;
  static const double caretWidth = 2;
  static const double caretHeight = 18;
  static const double thinkingDotSize = 6;
  static const int composerMaxLines = 6;
  static const double orbSize = 72;

  /// Extra delay per item when the empty state reveals itself.
  static const int revealStepMs = 60;

  static const double skeletonUserWidthFraction = 0.5;
  static const double skeletonAssistantWidthFraction = 0.8;
}
