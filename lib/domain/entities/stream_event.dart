import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/value_object.dart';

enum StreamFailureCode {
  unauthorized,
  rateLimited,
  network,
  idleTimeout,
  server,
  malformedStream,
  unknown,
}

enum FinishReason { stop, length, contentFilter, other }

/// Why a stream failed. [message] is developer-facing English; the UI must map
/// [code] to a localized string rather than showing [message].
final class StreamFailure extends ValueObject {
  const StreamFailure({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  final StreamFailureCode code;
  final String message;
  final int? statusCode;

  /// Server-suggested wait (e.g. from a 429 `Retry-After`), if any.
  final Duration? retryAfter;

  bool get isRetryable => switch (code) {
        StreamFailureCode.rateLimited ||
        StreamFailureCode.network ||
        StreamFailureCode.idleTimeout ||
        StreamFailureCode.server =>
          true,
        StreamFailureCode.unauthorized ||
        StreamFailureCode.malformedStream ||
        StreamFailureCode.unknown =>
          false,
      };

  @override
  List<Object?> get props =>
      <Object?>[code, message, statusCode, retryAfter];
}

/// Normalized events emitted by an [LlmClient] stream.
sealed class StreamEvent extends ValueObject {
  const StreamEvent();
}

/// A chunk of assistant text. [text] is never empty.
final class TokenEvent extends StreamEvent {
  const TokenEvent(this.text);

  final String text;

  @override
  List<Object?> get props => <Object?>[text];

  @override
  String toString() => 'TokenEvent(chars: ${text.length})';
}

/// RAG citations. Typically arrives before the first token.
final class SourcesEvent extends StreamEvent {
  SourcesEvent(List<SourceReference> sources)
      : sources = List<SourceReference>.unmodifiable(sources);

  final List<SourceReference> sources;

  @override
  List<Object?> get props => <Object?>[sources];
}

/// Terminal failure event. Always the last event of a failed stream.
final class ErrorEvent extends StreamEvent {
  const ErrorEvent(this.failure);

  final StreamFailure failure;

  @override
  List<Object?> get props => <Object?>[failure];
}

/// Terminal success event. Always the last event of a successful stream.
final class DoneEvent extends StreamEvent {
  const DoneEvent({this.finishReason = FinishReason.stop});

  final FinishReason finishReason;

  @override
  List<Object?> get props => <Object?>[finishReason];
}
