import 'package:ai_assistant/core/theme/app_palette.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Full-screen backdrop: a subtle vertical gradient plus two soft color glows
/// in opposite corners (positioned with directional APIs, so they mirror in
/// RTL). The glow is static, isolated in its own repaint boundary, and hidden
/// in high-contrast mode.
class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key, this.showGlow = true});

  /// Found by tests; present only when the glow layer is drawn.
  static const Key glowKey = ValueKey<String>('app_background_glow');

  final Widget child;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final bool glow = showGlow && !MediaQuery.highContrastOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: palette.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (glow)
            Positioned.fill(
              child: RepaintBoundary(
                key: glowKey,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: _GlowLayer(palette: palette),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _GlowLayer extends StatelessWidget {
  const _GlowLayer({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double size =
            constraints.biggest.shortestSide * AppBackdrop.glowDiameterFactor;
        final double inset = -size * AppBackdrop.glowOverhang;
        return Stack(
          children: <Widget>[
            PositionedDirectional(
              start: inset,
              top: inset,
              width: size,
              height: size,
              child: _Glow(color: palette.orbA),
            ),
            PositionedDirectional(
              end: inset,
              bottom: inset,
              width: size,
              height: size,
              child: _Glow(color: palette.orbC),
            ),
          ],
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color.withValues(alpha: AppBackdrop.glowAlpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
