import 'package:ai_assistant/core/localization/text_direction.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/glass_surface.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// The message input. Grows up to [AppChat.composerMaxLines] lines; the action
/// button is "send" normally and "stop" while a reply streams. The text field
/// takes its direction from what the user types, so English typed in the
/// Arabic UI is laid out left-to-right.
///
/// [onSend] returns whether the message was accepted; the field is cleared
/// only then, so a refused send never loses the user's text.
class Composer extends StatefulWidget {
  const Composer({
    required this.hint,
    required this.sendLabel,
    required this.stopLabel,
    required this.isStreaming,
    required this.canSend,
    required this.onSend,
    required this.onStop,
    super.key,
  });

  final String hint;
  final String sendLabel;
  final String stopLabel;
  final bool isStreaming;

  /// False disables sending (not configured, loading, another chat busy).
  final bool canSend;
  final bool Function(String text) onSend;
  final VoidCallback onStop;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;
  TextDirection? _direction;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final bool hasText = value.trim().isNotEmpty;
    final TextDirection direction = textDirectionFor(
      value,
      fallback: Directionality.of(context),
    );
    if (hasText != _hasText || direction != _direction) {
      setState(() {
        _hasText = hasText;
        _direction = direction;
      });
    }
  }

  void _submit() {
    if (!_hasText || !widget.canSend) return;
    if (widget.onSend(_controller.text)) {
      _controller.clear();
      setState(() {
        _hasText = false;
        _direction = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final motion = context.motion;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: GlassSurface(
          borderRadius: const BorderRadiusDirectional.all(
            Radius.circular(AppRadii.xl),
          ),
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.lg,
            end: AppSpacing.xs,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  minLines: 1,
                  maxLines: AppChat.composerMaxLines,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  textDirection: _direction,
                  style: text.bodyLarge,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: text.bodyLarge?.copyWith(
                      color: palette.textTertiary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AnimatedSwitcher(
                duration: motion.fast,
                child: widget.isStreaming
                    ? _RoundButton(
                        key: const ValueKey<String>('stop'),
                        label: widget.stopLabel,
                        icon: Icons.stop_rounded,
                        fill: palette.surfaceRaised,
                        iconColor: palette.accent,
                        outline: palette.accent,
                        onPressed: widget.onStop,
                      )
                    : _RoundButton(
                        key: const ValueKey<String>('send'),
                        label: widget.sendLabel,
                        icon: Icons.arrow_upward_rounded,
                        fill: palette.accent,
                        iconColor: palette.onAccent,
                        onPressed:
                            _hasText && widget.canSend ? _submit : null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.fill,
    required this.iconColor,
    required this.onPressed,
    super.key,
    this.outline,
  });

  final String label;
  final IconData icon;
  final Color fill;
  final Color iconColor;
  final Color? outline;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: label,
      haptic: PressHaptic.light,
      onPressed: onPressed,
      focusBorderRadius: const BorderRadiusDirectional.all(
        Radius.circular(AppRadii.pill),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: outline == null ? null : Border.all(color: outline!),
        ),
        child: SizedBox.square(
          dimension: AppSizes.minTouchTarget - AppSpacing.sm,
          child: Icon(icon, size: AppSizes.iconMd, color: iconColor),
        ),
      ),
    );
  }
}
