import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';

/// Input to a chat completion.
///
/// [messages] must be the committed history plus the new user message. It must
/// NOT include the in-flight assistant placeholder. Context-window truncation
/// is the caller's (repository's) responsibility.
final class ChatRequest {
  ChatRequest({
    required this.conversationId,
    required List<ChatMessage> messages,
    this.localeTag,
  }) : messages = List<ChatMessage>.unmodifiable(messages);

  final String conversationId;
  final List<ChatMessage> messages;

  /// BCP-47 tag (e.g. `ar`, `en`) hinting the reply language to the gateway.
  final String? localeTag;
}

/// Provider-agnostic streaming chat contract. The app only ever talks to the
/// edge gateway, never to a model provider; implementations live in `data/`.
///
/// Stream contract (implementations MUST honor it, consumers MAY rely on it):
///  1. Cold and single-subscription: the request starts when listened to.
///  2. Zero or more [TokenEvent] / [SourcesEvent], then exactly ONE terminal
///     event ([DoneEvent] or [ErrorEvent]), then the stream closes.
///  3. Expected failures (HTTP errors, timeouts, malformed data, idle gaps)
///     surface as an [ErrorEvent], never via `addError`.
///  4. Cancelling the subscription aborts the underlying request promptly. No
///     further events, and no terminal event, are emitted after cancel.
///  5. Idle-gap detection (default 20 s without bytes) is the implementation's
///     job and yields `StreamFailureCode.idleTimeout`.
abstract interface class LlmClient {
  Stream<StreamEvent> streamChat(ChatRequest request);
}
