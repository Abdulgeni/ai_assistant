import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_assistant/core/network/sse_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio adapter that serves scripted responses and records what it was asked.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];
  bool cancelRequested = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    if (cancelFuture != null) {
      unawaited(
        cancelFuture.then((_) {
          cancelRequested = true;
        }),
      );
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody sseBody(
  Stream<List<int>> chunks, {
  int status = 200,
  String contentType = 'text/event-stream',
  Map<String, List<String>> headers = const <String, List<String>>{},
}) =>
    ResponseBody(
      chunks.map(Uint8List.fromList),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
        ...headers,
      },
    );

/// One well-formed SSE event with a JSON payload.
String sseEvent(String event, Object? json) =>
    'event: $event\ndata: ${jsonEncode(json)}\n\n';

/// A finite byte stream, one network chunk per string.
Stream<List<int>> sseStream(List<String> chunks) =>
    Stream<List<int>>.fromIterable(chunks.map(utf8.encode));

SseClient sseClientFor(
  FakeAdapter adapter, {
  Duration firstByte = const Duration(seconds: 5),
  Duration idle = const Duration(seconds: 5),
}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://gateway.test'))
    ..httpClientAdapter = adapter;
  return SseClient(dio, firstByteTimeout: firstByte, idleTimeout: idle);
}

/// Wraps a test body in a zone that swallows Dio 5.7's mid-flight-cancel
/// zone error. Dio adds a cancel error to the response body stream when a
/// streamed request is cancelled before headers arrive; if no listener is
/// attached at that moment the error escapes to the test zone and fails the
/// test. Cancellation semantics are asserted via [FakeAdapter.cancelRequested].
void testInQuietZone(
  String description,
  Future<void> Function() body, {
  Timeout? timeout,
}) {
  test(description, () async {
    final Future<void>? future = runZonedGuarded<Future<void>>(
      body,
      (Object error, StackTrace stack) {
        if (error is DioException && error.type == DioExceptionType.cancel) {
          return;
        }
        Zone.current.parent?.handleUncaughtError(error, stack);
      },
    );
    if (future != null) await future;
    // Settle any pending microtasks (Dio cancel tokens, controller
    // close futures) so an unrelated running test cannot be flagged as
    // failed by an earlier test's leftover async work in the shared
    // flutter test isolate.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }, timeout: timeout);
}
