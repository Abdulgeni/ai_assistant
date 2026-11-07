import 'dart:async';

import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PressHaptic { none, selection, light }

/// Uniform tap feedback for any custom tappable.
///
///  * Hit target is at least [minSize] (48dp) even if [child] is smaller.
///  * Feedback: scales to [AppInteraction.pressedScale]; under reduce-motion
///    nothing moves and it dims instead.
///  * Works with touch, keyboard/switch activation (Enter/Space), and the
///    accessibility tap action.
///  * Shows a visible focus ring when focused.
///  * [semanticLabel], when set, REPLACES the child's own semantics, so pass a
///    complete localized label. When null, the child's semantics are used.
///
/// Pass `onPressed: null` for the disabled state.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    required this.onPressed,
    super.key,
    this.onLongPress,
    this.semanticLabel,
    this.haptic = PressHaptic.none,
    this.focusBorderRadius = const BorderRadiusDirectional.all(
      Radius.circular(AppRadii.md),
    ),
    this.minSize = AppSizes.minTouchTarget,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final PressHaptic haptic;
  final BorderRadiusGeometry focusBorderRadius;
  final double minSize;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
  }

  void _setPressed({required bool value}) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    final VoidCallback? callback = widget.onPressed;
    if (callback == null) return;
    switch (widget.haptic) {
      case PressHaptic.none:
        break;
      case PressHaptic.selection:
        unawaited(HapticFeedback.selectionClick());
      case PressHaptic.light:
        unawaited(HapticFeedback.lightImpact());
    }
    callback();
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final palette = context.palette;
    final bool pressed = _pressed && _enabled;

    final double scale =
        pressed && !motion.reduceMotion ? AppInteraction.pressedScale : 1;
    final double opacity = !_enabled
        ? AppInteraction.disabledOpacity
        : (pressed && motion.reduceMotion
            ? AppInteraction.reducedMotionPressedOpacity
            : 1);

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      onTap: _enabled ? _handleTap : null,
      onLongPress: _enabled ? widget.onLongPress : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor:
            _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (bool value) {
          if (_focused != value) setState(() => _focused = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (ActivateIntent intent) {
              _handleTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => _setPressed(value: true) : null,
          onTapUp: _enabled ? (_) => _setPressed(value: false) : null,
          onTapCancel: _enabled ? () => _setPressed(value: false) : null,
          onTap: _enabled ? _handleTap : null,
          onLongPress: _enabled ? widget.onLongPress : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.minSize,
              minHeight: widget.minSize,
            ),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: AnimatedOpacity(
                opacity: opacity,
                duration: motion.fast,
                child: AnimatedScale(
                  scale: scale,
                  duration: motion.fast,
                  curve: motion.standard,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.focusBorderRadius,
                      border: Border.all(
                        color:
                            _focused ? palette.accent : Colors.transparent,
                        width: AppInteraction.focusRingWidth,
                      ),
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
