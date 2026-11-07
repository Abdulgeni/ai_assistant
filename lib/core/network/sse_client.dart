import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_assistant/core/network/sse_exceptions.dart';
import 'package:ai_assistant/core/network/sse_parser.dart';
import 'package:dio/dio.dart';

/// Opens a POST request and exposes the response as a stream of SSE messages.
///
/// Behavior:
///  * Cold: nothing happens until the stream is listened to.
///  * Cancelling the subscription silences the stream. If the response has
///    already started arriving, the underlying request is aborted; if the
///    request is still in flight, it is allowed to complete without a
///    consumer (Dio 5.7 leaks a zone error if a streamed request is
///    cancelled before its response headers arrive).
///  * Two watchdogs, independent of Dio's timeouts: [firstByteTimeout] from
///    request start until response headers, then [idleTimeout] between
///    received chunks. Any bytes (including `: keep-alive` comments) count as
///    activity. `receiveTimeout` is disabled for these calls.
///  * Failures arrive as a single [SseException] error event followed by done.
///    A normal end of stream just completes; an unterminated trailing event is
///    dropped (see [SseParser.close]).
///
/// Gateway requirements for this client to behave:
///  * Send response headers immediately and a heartbeat comment at least every
///    ~10 s (less than [idleTimeout]).
///  * `Content-Type: text/event-stream`, no compression, blank line after
///    every event.
final class SseClient {
  SseClient(
    this._dio, {
    this.firstByteTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 20),
    this.limits = const SseLimits(),
    this.maxErrorBodyBytes = 16 * 1024,
  });

  final Dio _dio;
  final Duration firstByteTimeout;
  final Duration idleTimeout;
  final SseLimits limits;

  /// How much of a non-2xx body to read into [SseHttpException.body].
  final int maxErrorBodyBytes;

  Stream<SseMessage> post(
    String path, {
    Object? data,
    Map<String, Object?>? headers,
    Duration? firstByteTimeout,
    Duration? idleTimeout,
  }) {
    final Duration firstByte = firstByteTimeout ?? this.firstByteTimeout;
    final Duration idle = idleTimeout ?? this.idleTimeout;
    assert(firstByte > Duration.zero && idle > Duration.zero);

    final CancelToken cancelToken = CancelToken();
    late final StreamController<SseMessage> controller;
    StreamSubscription<SseMessage>? subscription;
    Timer? watchdog;
    var finished = false;

    void finish({
      Object? error,
      StackTrace? stackTrace,
      bool abort = true,
    }) {
      if (finished) return;
      finished = true;
      watchdog?.cancel();
      // Only abort the request if the response has already arrived. Aborting
      // mid-flight triggers a Dio 5.7 zone error from the response body
      // stream's controller, which we cannot observe.
      if (abort && !cancelToken.isCancelled) {
        cancelToken.cancel('SSE call finished');
      }
      unawaited(subscription?.cancel());
      if (error != null) controller.addError(error, stackTrace);
      unawaited(controller.close());
    }

    void arm(Duration timeout, {required bool beforeResponse}) {
      watchdog?.cancel();
      watchdog = Timer(timeout, () {
        finish(
          error: SseIdleTimeoutException(
            after: timeout,
            beforeResponse: beforeResponse,
          ),
          stackTrace: StackTrace.current,
        );
      });
    }

    Future<void> run() async {
      arm(firstByte, beforeResponse: true);
      try {
        final Response<ResponseBody> response = await _dio.post<ResponseBody>(
          path,
          data: data,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: Duration.zero,
            validateStatus: (int? _) => true,
            headers: <String, Object?>{
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
              'Accept-Encoding': 'identity',
              ...?headers,
            },
          ),
        );
        if (finished) {
          // The consumer cancelled before the response arrived. Silently
          // discard the response body to avoid unhandled-stream errors.
          _drainBodyStream(response.data);
          return;
        }

        arm(idle, beforeResponse: false);

        final ResponseBody? body = response.data;
        if (body == null) {
          throw const SseProtocolException('The response has no body.');
        }

        final int status = response.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          final String text = await _readErrorBody(body);
          throw SseHttpException(
            statusCode: status,
            body: text,
            retryAfter: _parseRetryAfter(
              response.headers['retry-after']?.first,
            ),
          );
        }

        final String contentType =
            response.headers[Headers.contentTypeHeader]?.first ?? '';
        if (!contentType.toLowerCase().contains('text/event-stream')) {
          throw SseProtocolException(
            'Expected text/event-stream but received "$contentType".',
          );
        }

        final Stream<Uint8List> bytes = body.stream.map((Uint8List chunk) {
          if (!finished) arm(idle, beforeResponse: false);
          return chunk;
        });

        subscription = decodeSseBytes(bytes, limits: limits).listen(
          (SseMessage message) {
            if (!finished) controller.add(message);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (finished) return;
            if (error is DioException &&
                error.type == DioExceptionType.cancel) {
              return;
            }
            finish(error: _mapError(error), stackTrace: stackTrace);
          },
          onDone: () => finish(abort: false),
          cancelOnError: true,
        );
      } on DioException catch (error, stackTrace) {
        if (error.type == DioExceptionType.cancel) {
          // We aborted the request ourselves; no error to surface.
          return;
        }
        if (finished) return;
        finish(error: _mapError(error), stackTrace: stackTrace);
      } on Object catch (error, stackTrace) {
        if (finished) return;
        finish(error: _mapError(error), stackTrace: stackTrace);
      }
    }

    controller = StreamController<SseMessage>(
      onListen: () => unawaited(run()),
      onCancel: () async {
        if (!finished) {
          finished = true;
          watchdog?.cancel();
          // Only cancel the token once the response has arrived; otherwise
          // Dio 5.7 throws a zone error from the response body's controller.
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('Cancelled by consumer');
          }
        }
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Subscribes to [body]'s stream with a no-op onError and immediately
  /// cancels the subscription. This consumes any pending Dio cancel error that
  /// would otherwise be added to a stream with no listener (a zone error).
  void _drainBodyStream(ResponseBody? body) {
    if (body == null) return;
    try {
      final StreamSubscription<Uint8List> drain =
          body.stream.listen(null, onError: (Object _) {});
      unawaited(drain.cancel());
    } on StateError {
      // Already listened to; ignore.
    } on Object {
      // Best-effort.
    }
  }

  Future<String> _readErrorBody(ResponseBody body) async {
    final List<int> bytes = <int>[];
    await for (final Uint8List chunk in body.stream) {
      bytes.addAll(chunk);
      if (bytes.length >= maxErrorBodyBytes) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final int? seconds = int.tryParse(value.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  static SseException _mapError(Object error) {
    if (error is SseException) return error;
    if (error is DioException) {
      final Object? inner = error.error;
      if (inner is SseException) return inner;
      return SseNetworkException(
        'Network error (${error.type.name})',
        cause: error,
      );
    }
    return SseNetworkException(
      'Network error (${error.runtimeType})',
      cause: error,
    );
  }
}
