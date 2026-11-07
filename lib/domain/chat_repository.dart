import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';

/// Local chat persistence. Implemented in `data/` (Drift); the presentation
/// layer never imports a database type.
abstract interface class ChatRepository {
  /// Conversations, most recently updated first. Re-emits on any change.
  Stream<List<Conversation>> watchConversations();

  /// Insert or update by [Conversation.id].
  Future<void> saveConversation(Conversation conversation);

  /// Deletes the conversation and all of its messages.
  Future<void> deleteConversation(String conversationId);

  /// Returns up to [limit] messages in chronological order (oldest first).
  ///
  /// With [beforeMessageId] null: the newest [limit] messages. Otherwise: the
  /// [limit] messages immediately preceding that message (for upward paging).
  Future<List<ChatMessage>> loadMessages(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
  });

  /// Upsert by [ChatMessage.id]. Streaming placeholders (status
  /// [MessageStatus.streaming]) may be saved; they are stored uncommitted.
  ///
  /// Also bumps the parent conversation's `updatedAt` to the message's
  /// `createdAt` if that is later. Throws [StateError] if the parent
  /// conversation does not exist.
  Future<void> saveMessage(ChatMessage message);

  Future<void> deleteMessage(String messageId);

  /// Marks every message left in the streaming state (app killed mid-reply) as
  /// [MessageStatus.failed], keeping whatever content was saved. Returns how
  /// many were fixed. Call once at startup, before loading any history.
  Future<int> recoverInterruptedStreams();

  /// Full-text search over message content (normalized for Arabic and Latin).
  /// Returns an empty list for a blank query. Ordering is best-effort
  /// relevance; callers must not rely on it.
  Future<List<ChatMessage>> searchMessages(String query, {int limit = 50});
}
