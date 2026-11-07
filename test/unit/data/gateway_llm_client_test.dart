import 'dart:async';
import 'dart:convert';

import 'package:ai_assistant/data/repositories/ai_repository_impl.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/llm_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sse_test_harness.dart';

ChatRequest _request({String? locale = 'ar'}) => ChatRequest(
      conversationId: 'c1',
      localeTag: locale,
      messages: <ChatMessage>[
        ChatMessage.user(
          id: 'm1',
          conversationId: 'c1',
          content: 'مرحبا',
          createdAt: DateTime(2026),
        ),
      ],
    );

Future<String?> _staticToken({required bool forceRefresh}) async => 'tok';

GatewayLlmClient _client(
  FakeAdapter adapter, {
  AuthTokenProvider? tokens,
  Duration idle = const Duration(seconds: 5),
}) =>
    GatewayLlmClient(
      sseClient: sseClientFor(adapter, idle: idle),
      authTokenProvider: tokens ?? _staticToken,
    );

ResponseBody _ok(List<String> events) => sseBody(sseStream(events));

ResponseBody _status(int status, {Map<String, List<String>>? headers}) =>
    sseBody(
      Stream<List<int>>.value(utf8.encode('{}')),
      status: status,
      contentType: 'application/json',
      headers: headers ?? const <String, List<String>>{},
    );

class _Run {
  _Run(Stream<StreamEvent> stream) {
    addTearDown(() => unawaited(subscription.cancel()));
    subscription = stream.listen(
      events.add,
      onError: errors.add,
      onDone: () {
        done = true;
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  late final StreamSubscription<StreamEvent> subscription;
  final List<StreamEvent> events = <StreamEvent>[];
  final List<Object> errors = <Object>[];
  final Completer<void> completer = Completer<void>();
  bool done = false;

  /// Completes when the stream closes, or — if a terminal event was already
  /// observed — immediately. A cancelled subscription never closes the
  /// stream, so a test that cancels must not rely on this to observe
  /// progress.
  Future<void> get completed {
    if (done || events.any((e) => e is DoneEvent || e is ErrorEvent)) {
      return Future<void>.value();
    }
    return completer.future.timeout(const Duration(seconds: 3));
  }

  int get terminalCount =>
      events.where((StreamEvent e) => e is DoneEvent || e is ErrorEvent).length;

  void expectContract() {
    expect(errors, isEmpty, reason: 'LlmClient must never call addError');
    expect(done, isTrue, reason: 'the stream must close');
    expect(terminalCount, 1, reason: 'exactly one terminal event');
    expect(
      events.last,
      anyOf(isA<DoneEvent>(), isA<ErrorEvent>()),
      reason: 'the terminal event must be last',
    );
  }
}

ErrorEvent _failure(
  StreamFailureCode code, {
  String message = '',
  int? status,
  Duration? retryAfter,
}) =>
    ErrorEvent(
      StreamFailure(
        code: code,
        message: message,
        statusCode: status,
        retryAfter: retryAfter,
      ),
    );

void main() {
  group('success', () {
    testInQuietZone('sources, tokens, done, then the stream closes', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          sseEvent('sources', <String, Object?>{
            'sources': <Object?>[
              <String, Object?>{'id': 's1', 'title': 'Doc', 'uri': 'https://x'},
            ],
          }),
          sseEvent('token', <String, Object?>{'text': 'مرحبا'}),
          sseEvent('token', <String, Object?>{'text': ' بك'}),
          sseEvent('done', <String, Object?>{'finishReason': 'stop'}),
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;

      expect(run.events, <StreamEvent>[
        SourcesEvent(const <SourceReference>[
          SourceReference(id: 's1', title: 'Doc', uri: 'https://x'),
        ]),
        const TokenEvent('مرحبا'),
        const TokenEvent(' بك'),
        const DoneEvent(),
      ]);
      run.expectContract();
    });

    testInQuietZone('the [DONE] sentinel ends the stream', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          sseEvent('token', <String, Object?>{'text': 'a'}),
          'data: [DONE]\n\n',
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events, <StreamEvent>[const TokenEvent('a'), const DoneEvent()]);
      run.expectContract();
    });

    testInQuietZone('unknown events and empty tokens are ignored', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          sseEvent('ping', <String, Object?>{}),
          sseEvent('token', <String, Object?>{'text': ''}),
          sseEvent('usage', <String, Object?>{'tokens': 3}),
          sseEvent('token', <String, Object?>{'text': 'a'}),
          sseEvent('done', <String, Object?>{}),
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events, <StreamEvent>[const TokenEvent('a'), const DoneEvent()]);
    });

    testInQuietZone('sends the encoded request with a bearer token', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async =>
            _ok(<String>[sseEvent('done', <String, Object?>{})]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      final RequestOptions options = adapter.requests.single;
      expect(options.path, GatewayLlmClient.defaultPath);
      expect(options.headers['Authorization'], 'Bearer tok');
      expect(options.data, <String, Object?>{
        'conversationId': 'c1',
        'locale': 'ar',
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': 'مرحبا'},
        ],
      });
    });
  });

  group('terminal events', () {
    testInQuietZone('tokens after done are never delivered', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          sseEvent('token', <String, Object?>{'text': 'a'}),
          sseEvent('done', <String, Object?>{}),
          sseEvent('token', <String, Object?>{'text': 'late'}),
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events, <StreamEvent>[const TokenEvent('a'), const DoneEvent()]);
      run.expectContract();
    });

    testInQuietZone('a server error event is terminal and drops what follows',
        () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          sseEvent('token', <String, Object?>{'text': 'a'}),
          sseEvent('error', <String, Object?>{
            'code': 'rate_limited',
            'message': 'slow',
            'retryAfterMs': 1500,
          }),
          sseEvent('token', <String, Object?>{'text': 'late'}),
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events, <StreamEvent>[
        const TokenEvent('a'),
        _failure(
          StreamFailureCode.rateLimited,
          message: 'slow',
          retryAfter: const Duration(milliseconds: 1500),
        ),
      ]);
      run.expectContract();
    });

    testInQuietZone(
        'a malformed token payload is a terminal malformedStream error',
        () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          'event: token\ndata: {nope\n\n',
          sseEvent('token', <String, Object?>{'text': 'late'}),
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events, hasLength(1));
      expect(
        (run.events.single as ErrorEvent).failure.code,
        StreamFailureCode.malformedStream,
      );
      run.expectContract();
    });

    testInQuietZone(
        'a stream that closes without done is a retryable network error',
        () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _ok(<String>[
          sseEvent('token', <String, Object?>{'text': 'a'}),
        ]),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events.first, const TokenEvent('a'));
      final ErrorEvent error = run.events.last as ErrorEvent;
      expect(error.failure.code, StreamFailureCode.network);
      expect(error.failure.isRetryable, isTrue);
      run.expectContract();
    });

    testInQuietZone('silence after headers becomes an idleTimeout error',
        () async {
      final StreamController<List<int>> body = StreamController<List<int>>();
      final FakeAdapter adapter =
          FakeAdapter((RequestOptions o) => Future<ResponseBody>.value(sseBody(body.stream)));
      final _Run run = _Run(
        _client(adapter, idle: const Duration(milliseconds: 80))
            .streamChat(_request()),
      );
      await run.completed;
      expect(
        (run.events.single as ErrorEvent).failure.code,
        StreamFailureCode.idleTimeout,
      );
      run.expectContract();
      unawaited(body.close());
    });
  });

  group('HTTP failures', () {
    testInQuietZone('429 carries Retry-After', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => _status(
          429,
          headers: <String, List<String>>{
            'retry-after': <String>['3'],
          },
        ),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      expect(run.events, <StreamEvent>[
        _failure(
          StreamFailureCode.rateLimited,
          message: 'HTTP 429',
          status: 429,
          retryAfter: const Duration(seconds: 3),
        ),
      ]);
      run.expectContract();
    });

    testInQuietZone('statuses map to the intended failure codes', () async {
      const Map<int, StreamFailureCode> expected = <int, StreamFailureCode>{
        500: StreamFailureCode.server,
        504: StreamFailureCode.idleTimeout,
        404: StreamFailureCode.unknown,
      };
      for (final MapEntry<int, StreamFailureCode> e in expected.entries) {
        final FakeAdapter adapter =
            FakeAdapter((RequestOptions o) async => _status(e.key));
        final _Run run = _Run(_client(adapter).streamChat(_request()));
        await run.completed;
        expect(
          (run.events.single as ErrorEvent).failure.code,
          e.value,
          reason: 'HTTP ${e.key}',
        );
        run.expectContract();
      }
    });

    testInQuietZone('a transport error is a retryable network failure',
        () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );
      final _Run run = _Run(_client(adapter).streamChat(_request()));
      await run.completed;
      final ErrorEvent error = run.events.single as ErrorEvent;
      expect(error.failure.code, StreamFailureCode.network);
      run.expectContract();
    });
  });

  group('authentication', () {
    testInQuietZone('a 401 refreshes the token once and retries', () async {
      final List<bool> refreshFlags = <bool>[];
      Future<String?> tokens({required bool forceRefresh}) async {
        refreshFlags.add(forceRefresh);
        return forceRefresh ? 'new' : 'old';
      }

      late final FakeAdapter adapter;
      adapter = FakeAdapter(
        (RequestOptions o) async => adapter.requests.length == 1
            ? _status(401)
            : _ok(<String>[
                sseEvent('token', <String, Object?>{'text': 'a'}),
                sseEvent('done', <String, Object?>{}),
              ]),
      );
      final _Run run =
          _Run(_client(adapter, tokens: tokens).streamChat(_request()));
      await run.completed;

      expect(refreshFlags, <bool>[false, true]);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].headers['Authorization'], 'Bearer old');
      expect(adapter.requests[1].headers['Authorization'], 'Bearer new');
      expect(run.events, <StreamEvent>[const TokenEvent('a'), const DoneEvent()]);
      run.expectContract();
    });

    testInQuietZone(
        'a second 401 is surfaced as unauthorized (no retry loop)', () async {
      final List<bool> refreshFlags = <bool>[];
      Future<String?> tokens({required bool forceRefresh}) async {
        refreshFlags.add(forceRefresh);
        return 'tok';
      }

      final FakeAdapter adapter =
          FakeAdapter((RequestOptions o) async => _status(401));
      final _Run run =
          _Run(_client(adapter, tokens: tokens).streamChat(_request()));
      await run.completed;

      expect(refreshFlags, <bool>[false, true]);
      expect(adapter.requests, hasLength(2));
      expect(run.events, <StreamEvent>[
        _failure(
          StreamFailureCode.unauthorized,
          message: 'HTTP 401',
          status: 401,
        ),
      ]);
      run.expectContract();
    });

    testInQuietZone('a failing token provider yields unauthorized and no request',
        () async {
      Future<String?> tokens({required bool forceRefresh}) async =>
          throw StateError('no session');
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async =>
            _ok(<String>[sseEvent('done', <String, Object?>{})]),
      );
      final _Run run =
          _Run(_client(adapter, tokens: tokens).streamChat(_request()));
      await run.completed;
      expect(adapter.requests, isEmpty);
      expect(
        (run.events.single as ErrorEvent).failure.code,
        StreamFailureCode.unauthorized,
      );
      run.expectContract();
    });

    testInQuietZone(
        'a null token sends the request without an Authorization header',
        () async {
      Future<String?> tokens({required bool forceRefresh}) async => null;
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async =>
            _ok(<String>[sseEvent('done', <String, Object?>{})]),
      );
      final _Run run =
          _Run(_client(adapter, tokens: tokens).streamChat(_request()));
      await run.completed;
      expect(adapter.requests.single.headers.containsKey('Authorization'),
          isFalse);
    });
  });

  group('cancellation and laziness', () {
    testInQuietZone(
        'cancelling aborts the request, with no events and no terminal event',
        () async {
      final StreamController<List<int>> body = StreamController<List<int>>();
      final FakeAdapter adapter =
          FakeAdapter((RequestOptions o) => Future<ResponseBody>.value(sseBody(body.stream)));
      final _Run run = _Run(_client(adapter).streamChat(_request()));

      body.add(utf8.encode(sseEvent('token', <String, Object?>{'text': 'a'})));
      await pumpEventQueue();
      expect(run.events, <StreamEvent>[const TokenEvent('a')]);

      unawaited(run.subscription.cancel());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(adapter.cancelRequested, isTrue);

      body.add(utf8.encode(sseEvent('token', <String, Object?>{'text': 'b'})));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(run.events, hasLength(1));
      expect(run.terminalCount, 0);
      expect(run.errors, isEmpty);
      unawaited(body.close());
    });

    testInQuietZone('cancelling while the token is being fetched sends no request',
        () async {
      final Completer<String?> gate = Completer<String?>();
      Future<String?> tokens({required bool forceRefresh}) => gate.future;
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async =>
            _ok(<String>[sseEvent('done', <String, Object?>{})]),
      );
      final _Run run =
          _Run(_client(adapter, tokens: tokens).streamChat(_request()));
      await pumpEventQueue();

      await run.subscription.cancel();
      gate.complete('tok');
      await pumpEventQueue();

      expect(adapter.requests, isEmpty);
      expect(run.events, isEmpty);
    });

    testInQuietZone('is cold: no request until listened to', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async =>
            _ok(<String>[sseEvent('done', <String, Object?>{})]),
      );
      _client(adapter).streamChat(_request());
      await pumpEventQueue();
      expect(adapter.requests, isEmpty);
    });

    testInQuietZone('is single-subscription', () async {
      final FakeAdapter adapter = FakeAdapter(
        (RequestOptions o) async =>
            _ok(<String>[sseEvent('done', <String, Object?>{})]),
      );
      final Stream<StreamEvent> stream = _client(adapter).streamChat(_request());
      final _Run run = _Run(stream);
      expect(() => stream.listen((_) {}), throwsStateError);
      await run.completed;
    });
  });
}
