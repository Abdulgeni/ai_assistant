import 'package:ai_assistant/core/network/sse_exceptions.dart';
import 'package:ai_assistant/data/models/stream_failure_mapper.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HTTP status', () {
    const Map<int, StreamFailureCode> expected = <int, StreamFailureCode>{
      401: StreamFailureCode.unauthorized,
      403: StreamFailureCode.unauthorized,
      408: StreamFailureCode.idleTimeout,
      429: StreamFailureCode.rateLimited,
      500: StreamFailureCode.server,
      502: StreamFailureCode.server,
      503: StreamFailureCode.server,
      504: StreamFailureCode.idleTimeout,
      400: StreamFailureCode.unknown,
      404: StreamFailureCode.unknown,
    };
    for (final MapEntry<int, StreamFailureCode> e in expected.entries) {
      test('${e.key} maps to ${e.value.name}', () {
        final StreamFailure failure =
            mapSseException(SseHttpException(statusCode: e.key));
        expect(failure.code, e.value);
        expect(failure.statusCode, e.key);
      });
    }

    test('carries Retry-After', () {
      final StreamFailure failure = mapSseException(
        const SseHttpException(
          statusCode: 429,
          retryAfter: Duration(seconds: 3),
        ),
      );
      expect(failure.retryAfter, const Duration(seconds: 3));
    });

    test('never copies the response body into the message', () {
      final StreamFailure failure = mapSseException(
        const SseHttpException(statusCode: 500, body: 'secret details'),
      );
      expect(failure.message, 'HTTP 500');
      expect(failure.message, isNot(contains('secret')));
    });
  });

  group('other exceptions', () {
    test('network', () {
      expect(
        mapSseException(const SseNetworkException('Network error (x)')).code,
        StreamFailureCode.network,
      );
    });

    test('idle timeout, before and after the response', () {
      for (final bool before in <bool>[true, false]) {
        expect(
          mapSseException(
            SseIdleTimeoutException(
              after: const Duration(seconds: 20),
              beforeResponse: before,
            ),
          ).code,
          StreamFailureCode.idleTimeout,
        );
      }
    });

    test('format and protocol errors are malformed streams', () {
      expect(
        mapSseException(const SseFormatException('bad')).code,
        StreamFailureCode.malformedStream,
      );
      expect(
        mapSseException(const SseProtocolException('bad')).code,
        StreamFailureCode.malformedStream,
      );
    });

    test('retryability follows the code', () {
      expect(
        mapSseException(const SseNetworkException('x')).isRetryable,
        isTrue,
      );
      expect(
        mapSseException(const SseHttpException(statusCode: 401)).isRetryable,
        isFalse,
      );
    });
  });
}
