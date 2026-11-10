import 'dart:async';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/text_direction.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/presentation/providers/conversation_providers.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side drawer listing conversations: open one, start a new chat, or delete
/// (with confirmation). Opens from the start edge, so it mirrors in RTL.
class ConversationsDrawer extends ConsumerWidget {
  const ConversationsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final palette = context.palette;
    final AsyncValue<List<Conversation>> list = ref.watch(conversationsProvider);
    final String? activeId = ref.watch(activeConversationProvider).valueOrNull;
    final ActiveConversationController controller =
        ref.read(activeConversationProvider.notifier);

    return Drawer(
      backgroundColor: palette.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.lg,
                end: AppSpacing.xs,
                top: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.conversations,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Pressable(
                    semanticLabel: l10n.newChat,
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(controller.startNewChat());
                    },
                    child: const Icon(
                      Icons.add_comment_rounded,
                      size: AppSizes.iconMd,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: list.when(
                data: (List<Conversation> items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Conversation conversation = items[index];
                    return _ConversationTile(
                      conversation: conversation,
                      selected: conversation.id == activeId,
                      onOpen: () {
                        Navigator.of(context).pop();
                        controller.open(conversation.id);
                      },
                      onDelete: () => _confirmDelete(
                        context,
                        l10n,
                        () => controller.deleteConversation(conversation.id),
                      ),
                    );
                  },
                ),
                loading: () => ChatSkeleton(label: l10n.loading),
                error: (Object error, StackTrace stackTrace) => Center(
                  child: Text(l10n.conversationLoadFailed),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
    Future<void> Function() onConfirmed,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.deleteChatTitle),
        content: Text(l10n.deleteChatBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await onConfirmed();
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final palette = context.palette;
    final String title =
        conversation.title.isEmpty ? l10n.newChat : conversation.title;

    return ListTile(
      selected: selected,
      selectedTileColor: palette.accentContainer,
      selectedColor: palette.onAccentContainer,
      onTap: onOpen,
      title: Directionality(
        textDirection:
            textDirectionFor(title, fallback: Directionality.of(context)),
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      trailing: Pressable(
        semanticLabel: l10n.delete,
        onPressed: onDelete,
        child: const Icon(Icons.delete_outline_rounded, size: AppSizes.iconMd),
      ),
    );
  }
}
