import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/entities/value_object.dart';

enum ChatLoadStatus { loading, ready, loadFailed }

/// Everything the chat screen renders EXCEPT the live text of the message
/// being streamed, which lives in the streaming buffer so that tokens never
/// rebuild the list.
final class ChatState extends ValueObject {
  const ChatState({
    this.status = ChatLoadStatus.loading,
    this.messages = const <ChatMessage>[],
    this.hasMoreOlder = false,
    this.isLoadingOlder = false,
    this.streamingMessageId,
    this.failure,
    this.storageError = false,
  });

  final ChatLoadStatus status;

  /// Oldest first. While a reply streams, the last element is the placeholder
  /// (status streaming, empty content).
  final List<ChatMessage> messages;
  final bool hasMoreOlder;
  final bool isLoadingOlder;

  /// Id of the assistant message currently receiving tokens, or null.
  final String? streamingMessageId;

  /// The last generation failure, cleared on the next send/regenerate or when
  /// dismissed. Developer-facing text: the UI maps `failure.code` to a
  /// localized message.
  final StreamFailure? failure;

  /// Set when any write to local storage failed (disk full, etc.). The
  /// conversation continues in memory but may not survive a restart.
  final bool storageError;

  bool get isStreaming => streamingMessageId != null;

  ChatState copyWith({
    ChatLoadStatus? status,
    List<ChatMessage>? messages,
    bool? hasMoreOlder,
    bool? isLoadingOlder,
    String? streamingMessageId,
    bool clearStreamingMessageId = false,
    StreamFailure? failure,
    bool clearFailure = false,
    bool? storageError,
  }) =>
      ChatState(
        status: status ?? this.status,
        messages: messages ?? this.messages,
        hasMoreOlder: hasMoreOlder ?? this.hasMoreOlder,
        isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
        streamingMessageId: clearStreamingMessageId
            ? null
            : (streamingMessageId ?? this.streamingMessageId),
        failure: clearFailure ? null : (failure ?? this.failure),
        storageError: storageError ?? this.storageError,
      );

  @override
  List<Object?> get props => <Object?>[
        status,
        messages,
        hasMoreOlder,
        isLoadingOlder,
        streamingMessageId,
        failure,
        storageError,
      ];

  @override
  String toString() =>
      'ChatState(${status.name}, messages: ${messages.length}, '
      'streaming: $streamingMessageId)';
}
