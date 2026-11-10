import 'dart:async';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/locale_support.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/app_background.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/presentation/a11y/chat_announcements.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/conversation_providers.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:ai_assistant/presentation/widgets/chat/composer.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_list.dart';
import 'package:ai_assistant/presentation/widgets/chat/status_banners.dart';
import 'package:ai_assistant/presentation/widgets/conversations/conversations_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat screen: app bar, conversation, notices, and composer.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<String> active = ref.watch(activeConversationProvider);

    return Scaffold(
      drawer: const ConversationsDrawer(),
      appBar: AppBar(
        title: Text(
          l10n.appTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          Pressable(
            semanticLabel: l10n.newChat,
            onPressed: () => unawaited(
              ref.read(activeConversationProvider.notifier).startNewChat(),
            ),
            child: const Icon(Icons.add_comment_rounded, size: AppSizes.iconMd),
          ),
          Pressable(
            semanticLabel: l10n.switchLanguage,
            onPressed: () => _toggleLocale(context, ref),
            child: const Icon(Icons.translate_rounded, size: AppSizes.iconMd),
          ),
          Pressable(
            semanticLabel: l10n.switchTheme,
            onPressed: () => _toggleTheme(context, ref),
            child: const Icon(Icons.brightness_6_rounded, size: AppSizes.iconMd),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentMaxWidth,
              ),
              child: active.when(
                data: (String id) => _ChatBody(key: ValueKey<String>(id), conversationId: id),
                loading: () => ChatSkeleton(label: l10n.loading),
                error: (Object error, StackTrace stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          l10n.conversationLoadFailed,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(activeConversationProvider),
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
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

class _ChatBody extends ConsumerWidget {
  const _ChatBody({required this.conversationId, super.key});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ChatState chat = ref.watch(chatNotifierProvider(conversationId));
    ref.listen<ChatState>(chatNotifierProvider(conversationId), (
      ChatState? previous,
      ChatState next,
    ) {
      final String? text =
          announcementFor(previous: previous, next: next, l10n: l10n);
      if (text != null) {
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            text,
            Directionality.of(context),
          ),
        );
      }
    });
    final bool configured = ref.watch(appConfigProvider).isConfigured;
    final bool anyStreaming =
        ref.watch(streamingBufferProvider.select((s) => s.isActive));
    final bool otherChatBusy = anyStreaming && !chat.isStreaming;
    final bool canSend =
        configured && chat.status == ChatLoadStatus.ready && !otherChatBusy;

    bool send(String text) {
      if (!canSend) return false;
      final bool sent =
          ref.read(chatNotifierProvider(conversationId).notifier).send(text);
      if (sent) {
        final int userMessages = ref
            .read(chatNotifierProvider(conversationId))
            .messages
            .where((ChatMessage m) => m.role == ChatRole.user)
            .length;
        if (userMessages == 1) {
          unawaited(
            ref
                .read(activeConversationProvider.notifier)
                .onMessageSent(conversationId, text),
          );
        }
      }
      return sent;
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: MessageList(
            conversationId: conversationId,
            onSuggestion: send,
          ),
        ),
        StatusBanners(
          configured: configured,
          otherChatBusy: otherChatBusy,
          storageError: chat.storageError,
        ),
        Composer(
          hint: l10n.composerHint,
          sendLabel: l10n.send,
          stopLabel: l10n.stopGenerating,
          isStreaming: chat.isStreaming,
          canSend: canSend,
          onSend: send,
          onStop: () => unawaited(
            ref.read(chatNotifierProvider(conversationId).notifier).stop(),
          ),
        ),
      ],
    );
  }
}

void _toggleLocale(BuildContext context, WidgetRef ref) {
  final Locale current = Localizations.localeOf(context);
  ref.read(localeProvider.notifier).setLocale(
        current.languageCode == 'ar' ? AppLocales.english : AppLocales.arabic,
      );
}

void _toggleTheme(BuildContext context, WidgetRef ref) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  ref
      .read(themeModeProvider.notifier)
      .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
}
