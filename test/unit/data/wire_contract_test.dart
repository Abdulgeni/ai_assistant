import 'package:ai_assistant/core/network/sse_parser.dart';
import 'package:ai_assistant/data/models/wire_contract.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';

SseMessage _msg(String event, String data) =>
    SseMessage(event: event, data: data);

ErrorEvent _malformed(String event) => ErrorEvent(
      StreamFailure(
        code: StreamFailureCode.malformedStream,
        message: 'Invalid "$event" event payload.',
      ),
    );

void main() {
  group('token', () {
    test('decodes Arabic text', () {
      expect(
        decodeStreamEvent(_msg('token', '{"text":"مرحبا"}')),
        const TokenEvent('مرحبا'),
      );
    });

    test('an empty token is ignored', () {
      expect(decodeStreamEvent(_msg('token', '{"text":""}')), isNull);
    });

    test('a missing, non-string, or unparsable payload is malformed', () {
      for (final String data in <String>['{}', '{"text":5}', '{nope', '[]', '']) {
        expect(decodeStreamEvent(_msg('token', data)), _malformed('token'),
            reason: data);
      }
    });
  });

  group('sources', () {
    test('decodes entries and fills a missing id', () {
      final StreamEvent? event = decodeStreamEvent(
        _msg(
          'sources',
          '{"sources":[{"id":"a","title":"One","uri":"https://x","snippet":"s"},'
              '{"title":"Two"}]}',
        ),
      );
      expect(
        event,
        SourcesEvent(const <SourceReference>[
          SourceReference(id: 'a', title: 'One', uri: 'https://x', snippet: 's'),
          SourceReference(id: 'source-1', title: 'Two'),
        ]),
      );
    });

    test('entries without a title, or not objects, are skipped', () {
      expect(
        decodeStreamEvent(
          _msg('sources', '{"sources":[{"id":"a"},"x",{"id":"b","title":"T"}]}'),
        ),
        SourcesEvent(const <SourceReference>[
          SourceReference(id: 'b', title: 'T'),
        ]),
      );
    });

    test('an empty list is ignored', () {
      expect(decodeStreamEvent(_msg('sources', '{"sources":[]}')), isNull);
    });

    test('a non-list payload is malformed', () {
      expect(
        decodeStreamEvent(_msg('sources', '{"sources":"x"}')),
        _malformed('sources'),
      );
    });
  });

  group('error', () {
    test('maps known codes, message, and retryAfterMs', () {
      expect(
        decodeStreamEvent(
          _msg(
            'error',
            '{"code":"rate_limited","message":"slow down","retryAfterMs":1500}',
          ),
        ),
        const ErrorEvent(
          StreamFailure(
            code: StreamFailureCode.rateLimited,
            message: 'slow down',
            retryAfter: Duration(milliseconds: 1500),
          ),
        ),
      );
    });

    test('every wire code maps to the intended failure code', () {
      const Map<String, StreamFailureCode> expected = <String, StreamFailureCode>{
        'unauthorized': StreamFailureCode.unauthorized,
        'rate_limited': StreamFailureCode.rateLimited,
        'server_error': StreamFailureCode.server,
        'timeout': StreamFailureCode.idleTimeout,
        'upstream_timeout': StreamFailureCode.idleTimeout,
        'something_new': StreamFailureCode.unknown,
      };
      for (final MapEntry<String, StreamFailureCode> e in expected.entries) {
        final ErrorEvent event = decodeStreamEvent(
          _msg('error', '{"code":"${e.key}"}'),
        )! as ErrorEvent;
        expect(event.failure.code, e.value, reason: e.key);
      }
    });

    test('an unparsable payload still yields a terminal unknown error', () {
      final ErrorEvent event =
          decodeStreamEvent(_msg('error', 'not json'))! as ErrorEvent;
      expect(event.failure.code, StreamFailureCode.unknown);
    });

    test('a negative retryAfterMs is ignored', () {
      final ErrorEvent event = decodeStreamEvent(
        _msg('error', '{"code":"rate_limited","retryAfterMs":-5}'),
      )! as ErrorEvent;
      expect(event.failure.retryAfter, isNull);
    });

    test('a long server message is truncated', () {
      final ErrorEvent event = decodeStreamEvent(
        _msg('error', '{"code":"server_error","message":"${'x' * 500}"}'),
      )! as ErrorEvent;
      expect(event.failure.message.length, 200);
    });
  });

  group('done', () {
    test('defaults to stop for empty, empty-object, and bad payloads', () {
      for (final String data in <String>['', '{}', 'garbage']) {
        expect(decodeStreamEvent(_msg('done', data)), const DoneEvent(),
            reason: data);
      }
    });

    test('maps finish reasons', () {
      const Map<String, FinishReason> expected = <String, FinishReason>{
        'stop': FinishReason.stop,
        'length': FinishReason.length,
        'content_filter': FinishReason.contentFilter,
        'weird': FinishReason.other,
      };
      for (final MapEntry<String, FinishReason> e in expected.entries) {
        expect(
          decodeStreamEvent(_msg('done', '{"finishReason":"${e.key}"}')),
          DoneEvent(finishReason: e.value),
          reason: e.key,
        );
      }
    });
  });

  group('unnamed and unknown events', () {
    test('the [DONE] sentinel is a terminal done', () {
      expect(decodeStreamEvent(_msg('message', '[DONE]')), const DoneEvent());
      expect(decodeStreamEvent(_msg('message', ' [DONE] ')), const DoneEvent());
    });

    test('other unnamed data is ignored', () {
      expect(decodeStreamEvent(_msg('message', 'hello')), isNull);
    });

    test('unknown event names are ignored', () {
      expect(decodeStreamEvent(_msg('ping', '{}')), isNull);
      expect(decodeStreamEvent(_msg('usage', '{"tokens":5}')), isNull);
    });
  });

  group('encodeChatRequest', () {
    final DateTime now = DateTime(2026);

    test('sends only role and content, plus conversation id and locale', () {
      final Map<String, Object?> body = encodeChatRequest(
        ChatRequest(
          conversationId: 'c1',
          localeTag: 'ar',
          messages: <ChatMessage>[
            ChatMessage.user(
              id: 'm1',
              conversationId: 'c1',
              content: 'مرحبا',
              createdAt: now,
            ),
            ChatMessage(
              id: 'm2',
              conversationId: 'c1',
              role: ChatRole.assistant,
              content: 'أهلًا',
              createdAt: now,
            ),
          ],
        ),
      );
      expect(body, <String, Object?>{
        'conversationId': 'c1',
        'locale': 'ar',
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': 'مرحبا'},
          <String, String>{'role': 'assistant', 'content': 'أهلًا'},
        ],
      });
    });

    test('omits locale when unknown', () {
      final Map<String, Object?> body = encodeChatRequest(
        ChatRequest(
          conversationId: 'c1',
          messages: <ChatMessage>[
            ChatMessage.user(
              id: 'm1',
              conversationId: 'c1',
              content: 'hi',
              createdAt: now,
            ),
          ],
        ),
      );
      expect(body.containsKey('locale'), isFalse);
    });

    test('rejects a streaming placeholder in debug builds', () {
      expect(
        () => encodeChatRequest(
          ChatRequest(
            conversationId: 'c1',
            messages: <ChatMessage>[
              ChatMessage.assistantPlaceholder(
                id: 'm2',
                conversationId: 'c1',
                createdAt: now,
              ),
            ],
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
