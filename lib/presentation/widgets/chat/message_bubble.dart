import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/text_direction.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/presentation/l10n/failure_messages.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One chat message. The user's bubble has a gradient and its tail at the
/// bottom END corner; the assistant's has a surface fill and its tail at the
/// bottom START corner. Both mirror automatically in RTL, and the text inside
/// takes its own direction from its first strong character.
///
/// For the message currently streaming, only [_StreamingBody] rebuilds per
/// token (it watches the streaming buffer); this widget does not.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    super.key,
    this.failure,
    this.onRetry,
  });

  final ChatMessage message;

  /// The failure to describe on a failed message (the newest one only).
  final StreamFailure? failure;

  /// Shown on a failed message when a retry is possible.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == ChatRole.user;
    final palette = context.palette;
    final AppLocalizations l10n = context.l10n;

    final BorderRadiusDirectional radius = BorderRadiusDirectional.only(
      topStart: const Radius.circular(AppRadii.lg),
      topEnd: const Radius.circular(AppRadii.lg),
      bottomStart: Radius.circular(isUser ? AppRadii.lg : AppRadii.xs),
      bottomEnd: Radius.circular(isUser ? AppRadii.xs : AppRadii.lg),
    );
    final double fraction = isUser
        ? AppSizes.bubbleMaxWidthFraction
        : AppChat.assistantBubbleMaxWidthFraction;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Align(
        alignment: isUser
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: constraints.maxWidth * fraction),
              child: Semantics(
                container: true,
                label: isUser ? l10n.roleUser : l10n.roleAssistant,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: isUser ? palette.userBubbleGradient : null,
                    color: isUser ? null : palette.assistantBubble,
                    borderRadius: radius,
                    border: isUser ? null : Border.all(color: palette.outline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: isUser
                        ? _UserContent(text: message.content)
                        : _AssistantContent(
                            message: message,
                            failure: failure,
                            onRetry: onRetry,
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _UserContent extends StatelessWidget {
  const _UserContent({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Directionality(
      textDirection:
          textDirectionFor(text, fallback: Directionality.of(context)),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: palette.onUserBubble),
      ),
    );
  }
}

class _AssistantContent extends StatelessWidget {
  const _AssistantContent({
    required this.message,
    required this.failure,
    required this.onRetry,
  });

  final ChatMessage message;
  final StreamFailure? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle bodyStyle =
        (text.bodyLarge ?? const TextStyle()).copyWith(color: palette.onAssistantBubble);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (message.status == MessageStatus.streaming)
          _StreamingBody(messageId: message.id, style: bodyStyle)
        else if (message.content.isNotEmpty)
          Directionality(
            textDirection: textDirectionFor(
              message.content,
              fallback: Directionality.of(context),
            ),
            child: Text(message.content, style: bodyStyle),
          ),
        if (message.status == MessageStatus.cancelled)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
            child: Text(
              l10n.messageStopped,
              style: text.labelMedium?.copyWith(color: palette.textTertiary),
            ),
          ),
        if (message.status == MessageStatus.failed)
          _FailureRow(failure: failure, onRetry: onRetry),
        if (message.sources.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
            child: Text(
              l10n.sourcesCount(message.sources.length),
              style: text.labelMedium?.copyWith(color: palette.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// The live text of the streaming message, plus a blinking caret. Shows the
/// thinking indicator until the first token arrives.
class _StreamingBody extends ConsumerWidget {
  const _StreamingBody({required this.messageId, required this.style});

  final String messageId;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String live = ref.watch(streamingTextProvider(messageId)) ?? '';
    if (live.isEmpty) return const ThinkingIndicator();
    return Directionality(
      textDirection: textDirectionFor(live, fallback: Directionality.of(context)),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: live),
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: StreamingCaret(),
            ),
          ],
        ),
        style: style,
      ),
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.failure, required this.onRetry});

  final StreamFailure? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final StreamFailure? current = failure;
    final String message = current == null
        ? l10n.messageFailed
        : streamFailureMessage(l10n, current.code);

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                size: AppSizes.iconSm,
                color: palette.danger,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: palette.onAssistantBubble,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Pressable(
              semanticLabel: l10n.retry,
              onPressed: onRetry,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  l10n.retry,
                  style: text.labelLarge?.copyWith(color: palette.accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Blinking caret shown at the end of streaming text. Static under
/// reduce-motion.
class StreamingCaret extends StatefulWidget {
  const StreamingCaret({super.key});

  @override
  State<StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.caretBlink,
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = context.motion.allowAmbientLoops;
    if (_animate) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
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
    final palette = context.palette;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => Opacity(
          opacity: _animate ? 0.2 + 0.8 * _controller.value : 1,
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.xxs),
          child: SizedBox(
            width: AppChat.caretWidth,
            height: AppChat.caretHeight,
            child: DecoratedBox(decoration: BoxDecoration(color: palette.accent)),
          ),
        ),
      ),
    );
  }
}

/// Three pulsing dots shown before the first token. Static under
/// reduce-motion. Announced to screen readers as "Thinking".
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.ambient,
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = context.motion.allowAmbientLoops;
    if (_animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacity(int index) {
    if (!_animate) return 0.6;
    final double phase = (_controller.value + index * 0.2) % 1;
    return 0.3 + 0.7 * (1 - (phase - 0.5).abs() * 2);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: context.l10n.thinking,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Opacity(
                    opacity: _opacity(i),
                    child: SizedBox.square(
                      dimension: AppChat.thinkingDotSize,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
