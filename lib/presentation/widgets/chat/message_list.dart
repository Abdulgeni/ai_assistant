import 'dart:async';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/core/theme/widgets/skeleton.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/widgets/chat/empty_state.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_actions.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_bubble.dart';
import 'package:ai_assistant/presentation/widgets/chat/sources_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The scrolling conversation.
///
///  * A REVERSE list: offset 0 is the newest message, so while a reply streams
///    the view stays pinned to the bottom, and paging in older history never
///    shifts what the user is reading.
///  * Scrolling more than [AppChat.pinThreshold] away shows "jump to latest".
///    Starting any new turn re-pins to the bottom.
///  * Only messages created after this screen opened animate in; history and
///    paged-in messages appear instantly.
///  * Known limitation: if the user scrolls up while a reply is still
///    streaming, the content they are reading drifts upward as the reply
///    grows (a reverse list anchors at the bottom).
class MessageList extends ConsumerStatefulWidget {
  const MessageList({
    required this.conversationId,
    required this.onSuggestion,
    super.key,
  });

  /// Found by tests; the fade wrapper of the jump-to-latest button.
  static const Key jumpButtonKey = ValueKey<String>('jump_to_latest');

  final String conversationId;
  final ValueChanged<String> onSuggestion;

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final ScrollController _controller = ScrollController();
  final ValueNotifier<bool> _showJump = ValueNotifier<bool>(false);
  final Set<String> _entranceDone = <String>{};
  late final DateTime _sessionStart;

  @override
  void initState() {
    super.initState();
    _sessionStart = ref.read(clockProvider)();
  }

  @override
  void dispose() {
    _controller.dispose();
    _showJump.dispose();
    super.dispose();
  }

  ChatNotifier get _notifier =>
      ref.read(chatNotifierProvider(widget.conversationId).notifier);

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    final motion = context.motion;
    unawaited(
      _controller.animateTo(
        0,
        duration: motion.normal,
        curve: motion.standard,
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final ScrollMetrics metrics = notification.metrics;
    _showJump.value = metrics.pixels > AppChat.pinThreshold;
    if (metrics.extentAfter < AppChat.loadOlderThreshold) {
      unawaited(_notifier.loadOlder());
    }
    return false;
  }

  void _showActions(
    BuildContext itemContext,
    ChatMessage message, {
    required bool canRegenerate,
  }) {
    unawaited(
      showMessageActions(
        context: itemContext,
        actions: ref.read(platformActionsProvider),
        message: message,
        canRegenerate: canRegenerate,
        onRegenerate: () {
          _notifier.regenerate();
        },
      ),
    );
  }

  void _showSources(BuildContext itemContext, ChatMessage message) {
    unawaited(
      showSourcesSheet(
        context: itemContext,
        actions: ref.read(platformActionsProvider),
        sources: message.sources,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String id = widget.conversationId;
    ref.listen<ChatState>(chatNotifierProvider(id), (
      ChatState? previous,
      ChatState next,
    ) {
      // A reply just started (send or regenerate): follow it.
      if (previous != null && !previous.isStreaming && next.isStreaming) {
        _scrollToBottom();
      }
    });
    final ChatState chat = ref.watch(chatNotifierProvider(id));
    final AppLocalizations l10n = context.l10n;

    switch (chat.status) {
      case ChatLoadStatus.loading:
        return ChatSkeleton(label: l10n.loading);
      case ChatLoadStatus.loadFailed:
        return _LoadFailed(onRetry: () => unawaited(_notifier.reload()));
      case ChatLoadStatus.ready:
        break;
    }
    if (chat.messages.isEmpty) {
      return EmptyState(onSuggestion: widget.onSuggestion);
    }

    final List<ChatMessage> messages = chat.messages;
    final int count = messages.length + (chat.isLoadingOlder ? 1 : 0);

    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _controller,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            itemCount: count,
            findChildIndexCallback: (Key key) {
              if (key is ValueKey<String>) {
                final int i =
                    messages.indexWhere((ChatMessage m) => m.id == key.value);
                if (i >= 0) return messages.length - 1 - i;
              }
              return null;
            },
            itemBuilder: (BuildContext context, int index) {
              if (index >= messages.length) return const _OlderLoader();
              final ChatMessage message = messages[messages.length - 1 - index];
              final bool isNewest = index == 0;
              final bool isStreaming = message.status == MessageStatus.streaming;
              final bool canRetry = isNewest &&
                  !chat.isStreaming &&
                  message.role == ChatRole.assistant &&
                  message.status == MessageStatus.failed;
              final bool canRegenerate = isNewest &&
                  !chat.isStreaming &&
                  message.role == ChatRole.assistant &&
                  !isStreaming;
              final bool animate = !_entranceDone.contains(message.id) &&
                  !message.createdAt.isBefore(_sessionStart);
              return KeyedSubtree(
                key: ValueKey<String>(message.id),
                child: _Entrance(
                  animate: animate,
                  onDone: () => _entranceDone.add(message.id),
                  child: Builder(
                    builder: (BuildContext itemContext) => MessageBubble(
                      message: message,
                      failure: isNewest ? chat.failure : null,
                      onRetry: canRetry
                          ? () {
                              _notifier.regenerate();
                            }
                          : null,
                      onLongPress: isStreaming
                          ? null
                          : () => _showActions(
                                itemContext,
                                message,
                                canRegenerate: canRegenerate,
                              ),
                      onOpenSources: message.sources.isEmpty
                          ? null
                          : () => _showSources(itemContext, message),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        PositionedDirectional(
          end: AppSpacing.lg,
          bottom: AppSpacing.sm,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showJump,
            builder: (BuildContext context, bool show, Widget? child) =>
                AnimatedOpacity(
              key: MessageList.jumpButtonKey,
              opacity: show ? 1 : 0,
              duration: context.motion.fast,
              child: IgnorePointer(
                ignoring: !show,
                child: ExcludeSemantics(
                  excluding: !show,
                  child: child,
                ),
              ),
            ),
            child: _JumpButton(onPressed: _scrollToBottom),
          ),
        ),
      ],
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.animate,
    required this.onDone,
    required this.child,
  });

  final bool animate;
  final VoidCallback onDone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    final motion = context.motion;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.normal,
      curve: motion.standard,
      onEnd: onDone,
      child: child,
      builder: (BuildContext context, double value, Widget? child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AppChat.entranceSlide),
          child: child,
        ),
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      semanticLabel: context.l10n.jumpToLatest,
      onPressed: onPressed,
      focusBorderRadius: const BorderRadiusDirectional.all(
        Radius.circular(AppRadii.pill),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          shape: BoxShape.circle,
          border: Border.all(color: palette.outlineStrong),
          boxShadow: AppShadows.soft(palette.textPrimary),
        ),
        child: const SizedBox.square(
          dimension: AppSizes.minTouchTarget - AppSpacing.sm,
          child: Icon(Icons.arrow_downward_rounded, size: AppSizes.iconMd),
        ),
      ),
    );
  }
}

class _OlderLoader extends StatelessWidget {
  const _OlderLoader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: SkeletonScope(child: SkeletonText(lines: 2)),
      );
}

/// Placeholder shown while the conversation history loads.
class ChatSkeleton extends StatelessWidget {
  const ChatSkeleton({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      semanticLabel: label,
      child: const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FractionallySizedBox(
                widthFactor: AppChat.skeletonUserWidthFraction,
                child: SkeletonBox(height: AppSizes.minTouchTarget),
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: AppChat.skeletonAssistantWidthFraction,
                child: SkeletonText(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.historyLoadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
