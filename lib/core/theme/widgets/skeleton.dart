import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Owns the single shimmer ticker shared by every [SkeletonBox] below it.
/// Use one scope per screen region, not one per box.
///
/// Under reduce-motion no ticker runs and boxes render as static blocks.
/// Semantics: all skeleton content is hidden from assistive tech; if
/// [semanticLabel] is set (pass a localized "Loading"), it is announced once.
class SkeletonScope extends StatefulWidget {
  const SkeletonScope({required this.child, super.key, this.semanticLabel});

  final Widget child;
  final String? semanticLabel;

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.ambient,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool animate = context.motion.allowAmbientLoops;
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? label = widget.semanticLabel;
    return _SkeletonInherited(
      animation: _controller,
      child: label == null
          ? ExcludeSemantics(child: widget.child)
          : Semantics(
              label: label,
              excludeSemantics: true,
              child: widget.child,
            ),
    );
  }
}

class _SkeletonInherited extends InheritedWidget {
  const _SkeletonInherited({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<_SkeletonInherited>()
      ?.animation;

  @override
  bool updateShouldNotify(_SkeletonInherited oldWidget) =>
      animation != oldWidget.animation;
}

/// A rounded placeholder block. Shimmers when inside an animating
/// [SkeletonScope]; otherwise it is a static block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = AppSpacing.lg,
    this.borderRadius = const BorderRadiusDirectional.all(
      Radius.circular(AppRadii.sm),
    ),
  });

  /// Null means "fill the available width".
  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Animation<double>? animation = _SkeletonInherited.maybeOf(context);
    final bool animate = animation != null && context.motion.allowAmbientLoops;

    if (!animate) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: borderRadius,
        ),
        child: SizedBox(width: width, height: height),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: <Color>[
                palette.surfaceRaised,
                palette.outline,
                palette.surfaceRaised,
              ],
              stops: const <double>[0.35, 0.5, 0.65],
              transform: _SlideGradientTransform(progress: animation.value),
            ),
          ),
          child: SizedBox(width: width, height: height),
        );
      },
    );
  }
}

/// Slides the gradient band across the box in the READING direction: left to
/// right in LTR, right to left in RTL.
class _SlideGradientTransform extends GradientTransform {
  const _SlideGradientTransform({required this.progress});

  /// 0..1 loop progress.
  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final double direction = textDirection == TextDirection.rtl ? -1 : 1;
    // -1 puts the band fully before the box, +1 fully after it.
    final double slide = progress * 2 - 1;
    return Matrix4.translationValues(
      bounds.width * slide * direction,
      0,
      0,
    );
  }
}

/// Placeholder paragraph: [lines] blocks, the last one shorter, aligned to
/// the start edge (so it hugs the right edge in RTL).
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, this.lines = 3})
      : assert(lines >= 1, 'lines must be at least 1');

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < lines; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSkeleton.lineGap),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: (i == lines - 1 && lines > 1)
                ? AppSkeleton.lastLineWidthFraction
                : 1,
            child: const SkeletonBox(height: AppSkeleton.lineHeight),
          ),
        ],
      ],
    );
  }
}
