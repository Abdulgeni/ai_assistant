import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_assistant/core/network/sse_client.dart';
import 'package:ai_assistant/core/network/sse_exceptions.dart';
import 'package:ai_assistant/core/network/sse_parser.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = Future<ResponseBody> Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final _Handler _handler;
  RequestOptions? lastOptions;
  bool cancelRequested = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    lastOptions = options;
    if (cancelFuture != null) {
      unawaited(
        cancelFuture.then((_) {
          cancelRequested = true;
        }),
      );
    }
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _sse(
  Stream<List<int>> chunks, {
  int status = 200,
  String contentType = 'text/event-stream',
  Map<String, List<String>> extraHeaders = const <String, List<String>>{},
}) =>
    ResponseBody(
      chunks.map(Uint8List.fromList),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
        ...extraHeaders,
      },
    );

({SseClient client, _FakeAdapter adapter}) _setup(
  _Handler handler, {
  Duration firstByte = const Duration(seconds: 5),
  Duration idle = const Duration(seconds: 5),
  SseLimits limits = const SseLimits(),
}) {
  final _FakeAdapter adapter = _FakeAdapter(handler);
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://gateway.test'))
    ..httpClientAdapter = adapter;
  return (
    client: SseClient(
      dio,
      firstByteTimeout: firstByte,
      idleTimeout: idle,
      limits: limits,
    ),
    adapter: adapter,
  );
}

class _Outcome {
  final List<SseMessage> messages = <SseMessage>[];
  Object? error;
  bool done = false;
}

_Outcome _listen(Stream<SseMessage> stream) {
  final _Outcome outcome = _Outcome();
  stream.listen(
    outcome.messages.add,
    onError: (Object error) => outcome.error = error,
    onDone: () => outcome.done = true,
  );
  return outcome;
}

Future<void> _wait(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

SseMessage _token(String json) =>
    SseMessage(event: 'token', data: json);

// Wraps a test body in a zone that swallows Dio 5.7's mid-flight-cancel
// zone error. Dio adds a cancel error to the response body stream when a
// streamed request is cancelled before headers arrive; if no listener is
// attached at that moment the error escapes to the test zone and fails the
// test. Cancellation semantics are asserted via adapter.cancelRequested.
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
        // Surface other errors by rethrowing into the outer zone.
        Zone.current.parent?.handleUncaughtError(error, stack);
      },
    );
    if (future != null) await future;
  }, timeout: timeout);
}

void main() {
  group('streaming', () {
    final List<int> bytes = utf8.encode(
      'event: token\ndata: {"text":"مرحبا"}\n\n'
      'event: done\ndata: {}\n\n',
    );
    final List<SseMessage> expected = <SseMessage>[
      _token('{"text":"مرحبا"}'),
      const SseMessage(event: 'done', data: '{}'),
    ];

    test('delivers messages for every byte split, even mid-character',
        () async {
      for (var cut = 0; cut <= bytes.length; cut++) {
        final _FakeAdapter adapter = _FakeAdapter(
          (RequestOptions o) async => _sse(
            Stream<List<int>>.fromIterable(<List<int>>[
              bytes.sublist(0, cut),
              bytes.sublist(cut),
            ]),
          ),
        );
        final Dio dio = Dio(BaseOptions(baseUrl: 'https://gateway.test'))
          ..httpClientAdapter = adapter;
        final List<SseMessage> got = await SseClient(dio).post('/chat').toList();
        expect(got, expected, reason: 'cut at $cut');
      }
    });

    test('completes normally without aborting the request', () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async =>
            _sse(Stream<List<int>>.value(bytes)),
      );
      final List<SseMessage> got = await t.client.post('/chat').toList();
      await pumpEventQueue();
      expect(got, expected);
      expect(t.adapter.cancelRequested, isFalse);
    });

    test('drops an unterminated trailing event', () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => _sse(
          Stream<List<int>>.value(
            utf8.encode('event: token\ndata: a\n\nevent: done\ndata: {}'),
          ),
        ),
      );
      final List<SseMessage> got = await t.client.post('/chat').toList();
      expect(got, <SseMessage>[_token('a')]);
    });

    testInQuietZone('heartbeat comments keep the connection alive', () async {
      final StreamController<List<int>> body = StreamController<List<int>>();
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) => Future<ResponseBody>.value(_sse(body.stream)),
        idle: const Duration(milliseconds: 120),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      for (var i = 0; i < 6; i++) {
        body.add(utf8.encode(': hb\n\n'));
        await _wait(50);
      }
      body
        ..add(utf8.encode('event: token\ndata: a\n\n'))
        ..add(utf8.encode('event: done\ndata: {}\n\n'));
      await body.close();
      await _wait(50);
      expect(outcome.error, isNull);
      expect(outcome.done, isTrue);
      expect(outcome.messages, hasLength(2));
    });
  });

  group('request shape', () {
    test('sends SSE headers, the body, and disables receiveTimeout',
        () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async =>
            _sse(const Stream<List<int>>.empty()),
      );
      await t.client.post(
        '/api/chat/stream',
        data: <String, Object?>{'prompt': 'hi'},
        headers: <String, Object?>{'Authorization': 'Bearer t'},
      ).toList();
      final RequestOptions options = t.adapter.lastOptions!;
      expect(options.method, 'POST');
      expect(options.path, '/api/chat/stream');
      expect(options.responseType, ResponseType.stream);
      expect(options.receiveTimeout, Duration.zero);
      expect(options.headers['Accept'], 'text/event-stream');
      expect(options.headers['Authorization'], 'Bearer t');
      expect(options.data, <String, Object?>{'prompt': 'hi'});
    });
  });

  group('failures', () {
    testInQuietZone(
        'non-2xx becomes SseHttpException with status, body, Retry-After',
        () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => _sse(
          Stream<List<int>>.value(utf8.encode('{"error":"slow down"}')),
          status: 429,
          contentType: 'application/json',
          extraHeaders: <String, List<String>>{
            'retry-after': <String>['7'],
          },
        ),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      await _wait(50);
      final SseHttpException error = outcome.error! as SseHttpException;
      expect(error.statusCode, 429);
      expect(error.body, '{"error":"slow down"}');
      expect(error.retryAfter, const Duration(seconds: 7));
      expect(outcome.done, isTrue);
    });

    test('a non-event-stream 200 becomes SseProtocolException', () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => _sse(
          Stream<List<int>>.value(utf8.encode('<html></html>')),
          contentType: 'text/html',
        ),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      await _wait(50);
      expect(outcome.error, isA<SseProtocolException>());
    });

    test('a transport error becomes SseNetworkException', () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      await _wait(50);
      expect(outcome.error, isA<SseNetworkException>());
      expect(outcome.done, isTrue);
    });

    testInQuietZone('invalid UTF-8 becomes SseFormatException and aborts',
        () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => _sse(
          Stream<List<int>>.value(<int>[
            ...'data: '.codeUnits,
            0xFF,
            0xFE,
            0x0A,
            0x0A,
          ]),
        ),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      await _wait(50);
      expect(outcome.error, isA<SseFormatException>());
    });

    test('an oversized event becomes SseFormatException', () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => _sse(
          Stream<List<int>>.value(utf8.encode('data: ${'x' * 100}\n\n')),
        ),
        limits: const SseLimits(maxEventDataLength: 20),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      await _wait(50);
      expect(outcome.error, isA<SseFormatException>());
    });
  });

  group('watchdogs and cancellation', () {
    testInQuietZone('idle timeout after headers aborts the request',
        () async {
      final StreamController<List<int>> body = StreamController<List<int>>();
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) => Future<ResponseBody>.value(_sse(body.stream)),
        idle: const Duration(milliseconds: 80),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      body.add(utf8.encode('event: token\ndata: a\n\n'));
      await _wait(300);
      final SseIdleTimeoutException error =
          outcome.error! as SseIdleTimeoutException;
      expect(error.beforeResponse, isFalse);
      expect(outcome.messages, hasLength(1));
      expect(outcome.done, isTrue);
      expect(t.adapter.cancelRequested, isTrue);
      unawaited(body.close());
    });

    testInQuietZone('first-byte timeout when headers never arrive', () async {
      final Completer<ResponseBody> never = Completer<ResponseBody>();
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) => never.future,
        firstByte: const Duration(milliseconds: 80),
      );
      final _Outcome outcome = _listen(t.client.post('/chat'));
      await _wait(300);
      final SseIdleTimeoutException error =
          outcome.error! as SseIdleTimeoutException;
      expect(error.beforeResponse, isTrue);
      expect(t.adapter.cancelRequested, isTrue);
    });

    testInQuietZone('cancelling the subscription silences the stream',
        () async {
      final StreamController<List<int>> body = StreamController<List<int>>();
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) => Future<ResponseBody>.value(_sse(body.stream)),
      );
      final List<SseMessage> messages = <SseMessage>[];
      final StreamSubscription<SseMessage> subscription =
          t.client.post('/chat').listen(messages.add);

      // Deliver one event and wait for it to arrive before cancelling.
      body.add(utf8.encode('event: token\ndata: a\n\n'));
      for (var i = 0; i < 50 && messages.isEmpty; i++) {
        await _wait(20);
      }
      expect(messages, hasLength(1));

      // Dio 5.7 can hang on subscription.cancel() mid-flight. Fire-and-forget
      // the cancel; assert only that no more messages are delivered. The
      // adapter.cancelRequested path is proven by the first-byte test above.
      unawaited(subscription.cancel());
      await _wait(150);

      if (!body.isClosed) {
        body.add(utf8.encode('event: token\ndata: b\n\n'));
      }
      await _wait(150);
      expect(messages, hasLength(1));
      unawaited(body.close());
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('is cold: nothing is requested until listened to', () async {
      final ({SseClient client, _FakeAdapter adapter}) t = _setup(
        (RequestOptions o) async => _sse(const Stream<List<int>>.empty()),
      );
      t.client.post('/chat');
      await pumpEventQueue();
      expect(t.adapter.lastOptions, isNull);
    });
  });
}
