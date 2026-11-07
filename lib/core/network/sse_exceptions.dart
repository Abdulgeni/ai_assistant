/// Failures of the SSE transport. The data layer maps these to domain
/// `StreamFailure`s; nothing above `data/` sees them.
sealed class SseException implements Exception {
  const SseException();

  /// Developer-facing description. Never contains URLs, headers, or payloads.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server answered with a non-2xx status.
final class SseHttpException extends SseException {
  const SseHttpException({
    required this.statusCode,
    this.body = '',
    this.retryAfter,
  });

  final int statusCode;

  /// Up to the first 16 KiB of the error body. Parse it, then discard it;
  /// never log it.
  final String body;

  /// From the `Retry-After` header when given in whole seconds.
  final Duration? retryAfter;

  @override
  String get message => 'HTTP $statusCode';
}

/// Connection failure, TLS failure, reset, or any transport error.
final class SseNetworkException extends SseException {
  const SseNetworkException(this.description, {this.cause});

  final String description;
  final Object? cause;

  @override
  String get message => description;
}

/// No bytes arrived within the allowed time.
final class SseIdleTimeoutException extends SseException {
  const SseIdleTimeoutException({
    required this.after,
    required this.beforeResponse,
  });

  final Duration after;

  /// True when the server never sent response headers (first-byte timeout).
  final bool beforeResponse;

  @override
  String get message => beforeResponse
      ? 'No response within ${after.inMilliseconds} ms'
      : 'No data for ${after.inMilliseconds} ms';
}

/// The bytes were not a valid event stream: bad UTF-8, or a line/event over
/// the configured size limit.
final class SseFormatException extends SseException {
  const SseFormatException(this.detail);

  final String detail;

  @override
  String get message => detail;
}

/// The response was not an event stream at all (wrong content type, no body).
final class SseProtocolException extends SseException {
  const SseProtocolException(this.detail);

  final String detail;

  @override
  String get message => detail;
}
