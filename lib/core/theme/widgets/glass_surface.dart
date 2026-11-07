import 'dart:ui' show ImageFilter;

import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// A frosted-glass panel: blurred backdrop, translucent fill, hairline border.
///
/// Rules of use:
///  * Put text on it only over a KNOWN backdrop. Contrast on translucent
///    surfaces depends on what is behind them and cannot be verified statically.
///  * Use sparingly (top bar, composer, voice overlay). Never inside list
///    items: every instance costs a full-screen-region blur on the GPU.
///  * Never wrap it in a RepaintBoundary: that limits the backdrop to the
///    boundary's own layer, so the blur would blur nothing.
///
/// It becomes a solid, bordered surface when [opaque] is true, or, when
/// [opaque] is null, when the OS high-contrast setting is on. Flutter exposes
/// no "reduce transparency" flag, so high contrast is the closest proxy.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.borderRadius = const BorderRadiusDirectional.all(
      Radius.circular(AppRadii.lg),
    ),
    this.padding = EdgeInsetsDirectional.zero,
    this.blurSigma = AppBlur.soft,
    this.opaque,
  });

  final Widget child;

  /// Directional so tailed shapes mirror in RTL.
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final double blurSigma;

  /// Force solid (true) or glass (false). Null follows the platform setting.
  final bool? opaque;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bool solid = opaque ?? MediaQuery.highContrastOf(context);
    final Widget content = Padding(padding: padding, child: child);

    if (solid) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: borderRadius,
          border: Border.all(color: palette.outlineStrong),
        ),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.glassFill,
            borderRadius: borderRadius,
            border: Border.all(color: palette.glassBorder),
          ),
          child: content,
        ),
      ),
    );
  }
}
