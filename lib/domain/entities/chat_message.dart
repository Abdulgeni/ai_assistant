import 'package:ai_assistant/domain/entities/value_object.dart';

enum ChatRole { system, user, assistant }

enum MessageStatus {
  /// Assistant message still receiving tokens. Lives only in memory until the
  /// stream ends; it is committed to storage once.
  streaming,
  complete,
  failed,
  cancelled,
}

/// A retrieval citation produced server-side by the RAG pipeline.
final class SourceReference extends ValueObject {
  const SourceReference({
    required this.id,
    required this.title,
    this.uri,
    this.snippet,
  });

  final String id;
  final String title;
  final String? uri;
  final String? snippet;

  @override
  List<Object?> get props => <Object?>[id, title, uri, snippet];
}

/// One message in a conversation. Immutable; treat [sources] as read-only.
///
/// Identity and time are injected (never generated here) so the domain stays
/// deterministic and testable.
final class ChatMessage extends ValueObject {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.complete,
    this.sources = const <SourceReference>[],
  });

  factory ChatMessage.user({
    required String id,
    required String conversationId,
    required String content,
    required DateTime createdAt,
  }) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        role: ChatRole.user,
        content: content,
        createdAt: createdAt,
      );

  /// Empty assistant message that tokens will stream into.
  factory ChatMessage.assistantPlaceholder({
    required String id,
    required String conversationId,
    required DateTime createdAt,
  }) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        role: ChatRole.assistant,
        content: '',
        createdAt: createdAt,
        status: MessageStatus.streaming,
      );

  final String id;
  final String conversationId;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final List<SourceReference> sources;

  /// False only while tokens are still arriving.
  bool get isCommitted => status != MessageStatus.streaming;

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    List<SourceReference>? sources,
  }) =>
      ChatMessage(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        status: status ?? this.status,
        sources: sources ?? this.sources,
      );

  @override
  List<Object?> get props => <Object?>[
        id,
        conversationId,
        role,
        content,
        createdAt,
        status,
        sources,
      ];

  // Never print message content.
  @override
  String toString() =>
      'ChatMessage(id: $id, role: ${role.name}, status: ${status.name}, '
      'chars: ${content.length})';
}
