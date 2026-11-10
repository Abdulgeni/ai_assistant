import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/presentation/l10n/failure_messages.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';

/// What a screen reader should be told when the chat state changes, or null
/// for nothing.
///
/// Deliberately sparse: one message when a reply starts, one when it ends.
/// Streaming text is never announced token by token, which would make a screen
/// reader unusable while a reply is arriving.
String? announcementFor({
  required ChatState? previous,
  required ChatState next,
  required AppLocalizations l10n,
}) {
  final bool wasStreaming = previous?.isStreaming ?? false;

  if (!wasStreaming && next.isStreaming) return l10n.thinking;

  if (wasStreaming && !next.isStreaming) {
    final String? id = previous!.streamingMessageId;
    ChatMessage? finished;
    for (final ChatMessage message in next.messages) {
      if (message.id == id) {
        finished = message;
        break;
      }
    }
    // The placeholder was removed: the reply was stopped before any text.
    if (finished == null) return l10n.messageStopped;
    return switch (finished.status) {
      MessageStatus.complete => l10n.responseReady,
      MessageStatus.cancelled => l10n.messageStopped,
      MessageStatus.failed => next.failure == null
          ? l10n.messageFailed
          : streamFailureMessage(l10n, next.failure!.code),
      MessageStatus.streaming => null,
    };
  }
  return null;
}
