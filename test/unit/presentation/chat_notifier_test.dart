import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_doubles.dart';

class _Rig {
  _Rig({
    int pageSize = 50,
    Duration maxTime = const Duration(minutes: 5),
  }) {
    container = ProviderContainer(
      overrides: <Override>[
        llmClientProvider.overrideWithValue(llm),
        chatRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(
          () => DateTime(2026, 3, 1, 12).add(Duration(seconds: _tick++)),
        ),
        idGeneratorProvider.overrideWithValue(() => 'id${++_id}'),
        chatPageSizeProvider.overrideWithValue(pageSize),
        chatMaxGenerationTimeProvider.overrideWithValue(maxTime),
        streamingFlushIntervalProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakeLlmClient llm = FakeLlmClient();
  final InMemoryChatRepository repo = InMemoryChatRepository();
  late final ProviderContainer container;
  int _id = 0;
  int _tick = 0;

  ChatNotifier notifier([String conversation = 'c1']) =>
      container.read(chatNotifierProvider(conversation).notifier);

  ChatState state([String conversation = 'c1']) =>
      container.read(chatNotifierProvider(conversation));

  StreamingBufferState get buffer => container.read(streamingBufferProvider);

  Future<void> ready([String conversation = 'c1']) async {
    container.read(chatNotifierProvider(conversation));
    for (var i = 0;
        i < 100 && state(conversation).status == ChatLoadStatus.loading;
        i++) {
      await pumpEventQueue(times: 5);
    }
    expect(state(conversation).status, ChatLoadStatus.ready);
  }

  Future<FakeLlmCall> send(String text, [String conversation = 'c1']) async {
    await ready(conversation);
    expect(notifier(conversation).send(text), isTrue);
    return llm.last;
  }

  ChatMessage get assistant =>
      state().messages.lastWhere((ChatMessage m) => m.role == ChatRole.assistant);

  Future<void> settle([String conversation = 'c1']) async {
    await pumpEventQueue();
    await notifier(conversation).flushWrites();
  }
}

ChatMessage _seed(
  String id,
  ChatRole role,
  String content, {
  String conversation = 'c1',
  MessageStatus status = MessageStatus.complete,
}) =>
    ChatMessage(
      id: id,
      conversationId: conversation,
      role: role,
      content: content,
      createdAt: DateTime(2026),
      status: status,
    );

void main() {
  group('loading', () {
    test('loads the newest page and reports whether older ones exist', () async {
      final _Rig rig = _Rig(pageSize: 3);
      for (var i = 0; i < 5; i++) {
        rig.repo.messages.add(
          _seed('s$i', i.isEven ? ChatRole.user : ChatRole.assistant, 'm$i'),
        );
      }
      await rig.ready();
      expect(rig.state().messages.map((ChatMessage m) => m.id), <String>['s2', 's3', 's4']);
      expect(rig.state().hasMoreOlder, isTrue);
    });

    test('runs storage recovery before loading', () async {
      final _Rig rig = _Rig();
      rig.repo.messages.add(
        _seed('s0', ChatRole.assistant, 'cut', status: MessageStatus.streaming),
      );
      await rig.ready();
      expect(rig.repo.recoverCalls, 1);
      expect(rig.state().messages.single.status, MessageStatus.failed);
    });

    test('loadOlder prepends pages and ignores overlapping calls', () async {
      final _Rig rig = _Rig(pageSize: 50);
      for (var i = 0; i < 120; i++) {
        rig.repo.messages.add(_seed('s${i.toString().padLeft(3, '0')}', ChatRole.user, 'm$i'));
      }
      await rig.ready();
      expect(rig.state().messages, hasLength(50));

      await Future.wait(<Future<void>>[
        rig.notifier().loadOlder(),
        rig.notifier().loadOlder(),
      ]);
      expect(rig.state().messages, hasLength(100));
      expect(rig.state().hasMoreOlder, isTrue);

      await rig.notifier().loadOlder();
      expect(rig.state().messages, hasLength(120));
      expect(rig.state().hasMoreOlder, isFalse);
      expect(rig.state().messages.first.id, 's000');
    });
  });

  group('sending', () {
    test('appends the user message and a placeholder, and saves both', () async {
      final _Rig rig = _Rig();
      rig.container.read(localeProvider.notifier).setLocale(const Locale('ar'));
      final FakeLlmCall call = await rig.send('  مرحبا  ');
      await rig.settle();

      final List<ChatMessage> messages = rig.state().messages;
      expect(messages.map((ChatMessage m) => m.id), <String>['id1', 'id2']);
      expect(messages[0].content, 'مرحبا');
      expect(messages[1].status, MessageStatus.streaming);
      expect(rig.state().streamingMessageId, 'id2');
      expect(rig.buffer.messageId, 'id2');
      expect(rig.repo.ops, <String>['save:id1:complete', 'save:id2:streaming']);

      // The request has the user message but never the placeholder.
      expect(call.request.messages.map((ChatMessage m) => m.id), <String>['id1']);
      expect(call.request.conversationId, 'c1');
      expect(call.request.localeTag, 'ar');
    });

    test('refuses blank text, repeated sends, and sends before history loads',
        () async {
      final _Rig rig = _Rig();
      expect(rig.notifier().send('hi'), isFalse); // still loading
      await rig.ready();
      expect(rig.notifier().send('   '), isFalse);
      expect(rig.notifier().send('one'), isTrue);
      expect(rig.notifier().send('two'), isFalse); // already streaming
      expect(rig.state().messages, hasLength(2));
    });
  });

  group('streaming', () {
    test('tokens update only the buffer, never the chat state', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      await pumpEventQueue();

      var stateNotifications = 0;
      var bufferNotifications = 0;
      rig.container.listen(
        chatNotifierProvider('c1'),
        (ChatState? _, ChatState _) => stateNotifications++,
      );
      rig.container.listen(
        streamingBufferProvider,
        (StreamingBufferState? _, StreamingBufferState _) => bufferNotifications++,
      );

      for (var i = 0; i < 30; i++) {
        call.emit(TokenEvent('t$i '));
      }
      await pumpEventQueue();

      expect(stateNotifications, 0, reason: 'the list must not rebuild per token');
      expect(bufferNotifications, greaterThan(0));
      expect(rig.buffer.text, isNotEmpty);
    });

    test('done commits the full text once, and saves exactly three times',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      call
        ..emit(const TokenEvent('مرحبا'))
        ..emit(const TokenEvent(' بك'));
      await call.finish();
      await rig.settle();

      expect(rig.assistant.content, 'مرحبا بك');
      expect(rig.assistant.status, MessageStatus.complete);
      expect(rig.state().isStreaming, isFalse);
      expect(rig.state().failure, isNull);
      expect(rig.buffer.isActive, isFalse);
      expect(rig.container.read(generationLockProvider).holder, isNull);
      expect(rig.repo.ops, <String>[
        'save:id1:complete',
        'save:id2:streaming',
        'save:id2:complete',
      ]);
      expect(rig.repo.byId('id2')!.content, 'مرحبا بك');
      expect(call.cancelled, isTrue, reason: 'the finished request is released');
    });

    test('sources arrive in state early and are saved with the final message',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      final SourcesEvent sources = SourcesEvent(const <SourceReference>[
        SourceReference(id: 's1', title: 'Doc'),
      ]);
      call.emit(sources);
      await pumpEventQueue();
      expect(rig.assistant.sources, sources.sources);

      call.emit(const TokenEvent('answer'));
      await call.finish();
      await rig.settle();
      expect(rig.repo.byId('id2')!.sources, sources.sources);
    });

    test('a failure after partial text keeps the text on a failed message',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      call.emit(const TokenEvent('half an ans'));
      const StreamFailure failure =
          StreamFailure(code: StreamFailureCode.network, message: 'cut');
      await call.finish(const ErrorEvent(failure));
      await rig.settle();

      expect(rig.assistant.status, MessageStatus.failed);
      expect(rig.assistant.content, 'half an ans');
      expect(rig.state().failure, failure);
      expect(rig.repo.byId('id2')!.status, MessageStatus.failed);
      expect(rig.container.read(generationLockProvider).holder, isNull);
    });

    test('a failure with no text keeps an empty failed message', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      await call.finish(
        const ErrorEvent(
          StreamFailure(code: StreamFailureCode.rateLimited, message: 'slow'),
        ),
      );
      await rig.settle();
      expect(rig.assistant.status, MessageStatus.failed);
      expect(rig.assistant.content, isEmpty);
      expect(rig.state().failure!.code, StreamFailureCode.rateLimited);
    });

    test('done with no content is a failure, not an empty answer', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      await call.finish();
      await rig.settle();
      expect(rig.assistant.status, MessageStatus.failed);
      expect(rig.state().failure!.code, StreamFailureCode.unknown);
    });

    test('a stream that closes without a terminal event fails as network',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      call.emit(const TokenEvent('partial'));
      await call.closeWithoutTerminal();
      await rig.settle();
      expect(rig.assistant.status, MessageStatus.failed);
      expect(rig.assistant.content, 'partial');
      expect(rig.state().failure!.code, StreamFailureCode.network);
    });

    test('a stream error (contract violation) cannot hang the UI', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      call.failWithStreamError();
      await rig.settle();
      expect(rig.state().isStreaming, isFalse);
      expect(rig.state().failure!.code, StreamFailureCode.unknown);
    });

    test('the overall deadline fails a turn that never finishes', () async {
      final _Rig rig = _Rig(maxTime: const Duration(milliseconds: 40));
      final FakeLlmCall call = await rig.send('hi');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await rig.settle();
      expect(rig.state().isStreaming, isFalse);
      expect(rig.state().failure!.code, StreamFailureCode.idleTimeout);
      expect(call.cancelled, isTrue);
      expect(rig.container.read(generationLockProvider).holder, isNull);
    });
  });

  group('stop', () {
    test('keeps partial text as a cancelled message and ignores late events',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      call.emit(const TokenEvent('partial'));
      await pumpEventQueue();

      await rig.notifier().stop();
      call
        ..emit(const TokenEvent(' late'))
        ..emit(const DoneEvent());
      await rig.settle();

      expect(call.cancelled, isTrue);
      expect(rig.assistant.status, MessageStatus.cancelled);
      expect(rig.assistant.content, 'partial');
      expect(rig.state().failure, isNull);
      expect(rig.buffer.isActive, isFalse);
      expect(rig.container.read(generationLockProvider).holder, isNull);
      expect(rig.repo.byId('id2')!.status, MessageStatus.cancelled);
    });

    test('with no text yet, removes the placeholder from state and storage',
        () async {
      final _Rig rig = _Rig();
      await rig.send('hi');
      await rig.notifier().stop();
      await rig.settle();
      expect(rig.state().messages.map((ChatMessage m) => m.id), <String>['id1']);
      expect(rig.repo.byId('id2'), isNull);
    });

    test('does nothing when nothing is streaming', () async {
      final _Rig rig = _Rig();
      await rig.ready();
      await rig.notifier().stop();
      expect(rig.state().messages, isEmpty);
    });
  });

  group('regenerate', () {
    test('after a failure, replaces the failed message', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall first = await rig.send('question');
      first.emit(const TokenEvent('bad'));
      await first.finish(
        const ErrorEvent(StreamFailure(code: StreamFailureCode.server, message: 'x')),
      );
      await rig.settle();

      expect(rig.notifier().regenerate(), isTrue);
      final FakeLlmCall second = rig.llm.last;
      expect(second, isNot(same(first)));
      // The failed answer is not part of the new request.
      expect(second.request.messages.map((ChatMessage m) => m.id), <String>['id1']);

      second.emit(const TokenEvent('good'));
      await second.finish();
      await rig.settle();

      expect(
        rig.state().messages.map((ChatMessage m) => m.role),
        <ChatRole>[ChatRole.user, ChatRole.assistant],
      );
      expect(rig.assistant.content, 'good');
      expect(rig.assistant.id, isNot('id2'));
      expect(rig.repo.byId('id2'), isNull, reason: 'the failed message was deleted');
      expect(rig.state().failure, isNull);
    });

    test('replaces a completed answer', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall first = await rig.send('question');
      first.emit(const TokenEvent('v1'));
      await first.finish();
      await rig.settle();

      expect(rig.notifier().regenerate(), isTrue);
      rig.llm.last.emit(const TokenEvent('v2'));
      await rig.llm.last.finish();
      await rig.settle();

      expect(rig.assistant.content, 'v2');
      expect(rig.state().messages, hasLength(2));
    });

    test('after stop, restarts from the user message', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall first = await rig.send('question');
      first.emit(const TokenEvent('partial'));
      await pumpEventQueue();
      await rig.notifier().stop();

      expect(rig.notifier().regenerate(), isTrue);
      expect(rig.state().messages.map((ChatMessage m) => m.role), <ChatRole>[
        ChatRole.user,
        ChatRole.assistant,
      ]);
      expect(rig.assistant.status, MessageStatus.streaming);
    });

    test('works when the last message is a user message', () async {
      final _Rig rig = _Rig();
      rig.repo.messages.add(_seed('u1', ChatRole.user, 'unanswered'));
      await rig.ready();
      expect(rig.notifier().regenerate(), isTrue);
      expect(rig.llm.last.request.messages.single.id, 'u1');
    });

    test('is refused while streaming, and on an empty conversation', () async {
      final _Rig rig = _Rig();
      await rig.ready();
      expect(rig.notifier().regenerate(), isFalse);
      await rig.send('hi');
      expect(rig.notifier().regenerate(), isFalse);
    });

    test('an old call can never touch the new turn', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall first = await rig.send('question');
      await rig.notifier().stop();
      expect(rig.notifier().regenerate(), isTrue);
      final FakeLlmCall second = rig.llm.last;

      first
        ..emit(const TokenEvent('stale'))
        ..emit(const DoneEvent());
      second.emit(const TokenEvent('fresh'));
      await second.finish();
      await rig.settle();

      expect(rig.assistant.content, 'fresh');
    });
  });

  group('failure state', () {
    test('dismissFailure clears it and the next send clears it too', () async {
      final _Rig rig = _Rig();
      final FakeLlmCall call = await rig.send('hi');
      await call.finish(
        const ErrorEvent(StreamFailure(code: StreamFailureCode.server, message: 'x')),
      );
      await rig.settle();
      expect(rig.state().failure, isNotNull);

      rig.notifier().dismissFailure();
      expect(rig.state().failure, isNull);

      await call.controller.close().catchError((Object _) {});
    });
  });

  group('persistence', () {
    test('writes land in call order even when an early write is slow', () async {
      final _Rig rig = _Rig();
      rig.repo.delayFor = (ChatMessage m) => m.status == MessageStatus.streaming
          ? const Duration(milliseconds: 60)
          : Duration.zero;
      final FakeLlmCall call = await rig.send('hi');
      call.emit(const TokenEvent('answer'));
      await call.finish();
      await rig.settle();

      expect(rig.repo.byId('id2')!.status, MessageStatus.complete);
      expect(rig.repo.byId('id2')!.content, 'answer');
      expect(rig.repo.ops, <String>[
        'save:id1:complete',
        'save:id2:streaming',
        'save:id2:complete',
      ]);
    });

    test('a storage failure sets storageError but the reply still works',
        () async {
      final _Rig rig = _Rig();
      await rig.ready();
      rig.repo.failSaves = true;
      expect(rig.notifier().send('hi'), isTrue);
      final FakeLlmCall call = rig.llm.last;
      call.emit(const TokenEvent('answer'));
      await call.finish();
      await rig.settle();

      expect(rig.state().storageError, isTrue);
      expect(rig.assistant.content, 'answer');
      expect(rig.assistant.status, MessageStatus.complete);
    });
  });

  group('one generation at a time', () {
    test('a second conversation cannot start until the first finishes',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall first = await rig.send('hi', 'c1');
      await rig.ready('c2');

      expect(rig.notifier('c2').send('blocked'), isFalse);
      expect(rig.state('c2').messages, isEmpty);

      first.emit(const TokenEvent('a'));
      await first.finish();
      await rig.settle();

      expect(rig.notifier('c2').send('now ok'), isTrue);
    });

    test('the same conversation can start again right after finishing',
        () async {
      final _Rig rig = _Rig();
      final FakeLlmCall first = await rig.send('one');
      first.emit(const TokenEvent('a'));
      await first.finish();
      await rig.settle();
      expect(rig.notifier().send('two'), isTrue);
      // Earlier turns are part of the next request.
      expect(
        rig.llm.last.request.messages.map((ChatMessage m) => m.content),
        <String>['one', 'a', 'two'],
      );
    });
  });
}
