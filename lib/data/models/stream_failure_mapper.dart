import 'package:ai_assistant/core/network/sse_exceptions.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';

/// Converts a transport exception into a domain [StreamFailure]. The switch is
/// exhaustive over the sealed [SseException], so a new exception type will not
/// compile until it is mapped. Messages never contain response bodies.
StreamFailure mapSseException(SseException exception) => switch (exception) {
      final SseHttpException e => _mapHttp(e),
      final SseNetworkException e => StreamFailure(
          code: StreamFailureCode.network,
          message: e.message,
        ),
      final SseIdleTimeoutException e => StreamFailure(
          code: StreamFailureCode.idleTimeout,
          message: e.message,
        ),
      final SseFormatException e => StreamFailure(
          code: StreamFailureCode.malformedStream,
          message: e.message,
        ),
      final SseProtocolException e => StreamFailure(
          code: StreamFailureCode.malformedStream,
          message: e.message,
        ),
    };

StreamFailure _mapHttp(SseHttpException e) {
  final StreamFailureCode code = switch (e.statusCode) {
    401 || 403 => StreamFailureCode.unauthorized,
    408 || 504 => StreamFailureCode.idleTimeout,
    429 => StreamFailureCode.rateLimited,
    >= 500 => StreamFailureCode.server,
    _ => StreamFailureCode.unknown,
  };
  return StreamFailure(
    code: code,
    message: e.message,
    statusCode: e.statusCode,
    retryAfter: e.retryAfter,
  );
}
