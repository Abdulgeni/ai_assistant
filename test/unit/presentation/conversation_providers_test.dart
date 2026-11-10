import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/conversation_providers.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_doubles.dart';

Conversation _conv(String id, {String title = '', int updated = 0}) =>
    Conversation(
      id: id,
      title: title,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026).add(Duration(seconds: updated)),
    );

class _Rig {
  _Rig() {
    container = ProviderContainer(
      overrides: <Override>[
        chatRepositoryProvider.overrideWithValue(repo),
        llmClientProvider.overrideWithValue(FakeLlmClient()),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 1, 12)),
        idGeneratorProvider.overrideWithValue(() => 'new${++_id}'),
        streamingFlushIntervalProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
  }

  final InMemoryChatRepository repo = InMemoryChatRepository();
  late final ProviderContainer container;
  int _id = 0;

  ActiveConversationController get controller =>
      container.read(activeConversationProvider.notifier);

  Future<String> active() => container.read(activeConversationProvider.future);

  Future<void> chatReady(String id) async {
    container.read(chatNotifierProvider(id));
    for (var i = 0;
        i < 100 &&
            container.read(chatNotifierProvider(id)).status ==
                ChatLoadStatus.loading;
        i++) {
      await pumpEventQueue(times: 5);
    }
  }
}

void main() {
  group('deriveTitle', () {
    test('collapses whitespace and uses the first non-empty line', () {
      expect(deriveTitle('  hello   world  '), 'hello world');
      expect(deriveTitle('\n\n  first line\nsecond line'), 'first line');
    });

    test('blank input gives an empty title', () {
      expect(deriveTitle(''), isEmpty);
      expect(deriveTitle('   \n \t '), isEmpty);
    });

    test('cuts at 40 characters with an ellipsis', () {
      expect(deriveTitle('x' * 40), 'x' * 40);
      expect(deriveTitle('x' * 41), '${'x' * 40}…');
    });

    test('counts characters, not UTF-16 units (emoji, Arabic)', () {
      expect(deriveTitle('😀' * 45), '${'😀' * 40}…');
      const String arabic =
          'اشرح لي مفهوم الذكاء الاصطناعي بكلمات بسيطة جدا وسهلة الفهم للجميع';
      final String title = deriveTitle(arabic);
      expect(title.runes.length, lessThanOrEqualTo(41));
      expect(title, endsWith('…'));
      expect(arabic, startsWith(title.substring(0, title.length - 1)));
    });

    test('no trailing space before the ellipsis', () {
      final String title = deriveTitle('word ' * 20);
      expect(title, endsWith('…'));
      expect(title, isNot(endsWith(' …')));
    });
  });

  group('ActiveConversationController', () {
    test('creates the first conversation when there are none', () async {
      final _Rig rig = _Rig();
      expect(await rig.active(), 'new1');
      expect(rig.repo.conversations.keys, <String>['new1']);
    });

    test('opens the most recently updated conversation', () async {
      final _Rig rig = _Rig();
      rig.repo.conversations['a'] = _conv('a', updated: 5);
      rig.repo.conversations['b'] = _conv('b', updated: 50);
      expect(await rig.active(), 'b');
      expect(rig.repo.conversations, hasLength(2));
    });

    test('startNewChat reuses the current chat while it is still empty',
        () async {
      final _Rig rig = _Rig();
      final String first = await rig.active();
      await rig.chatReady(first);
      await rig.controller.startNewChat();
      expect(await rig.active(), first);
      expect(rig.repo.conversations, hasLength(1));
    });

    test('startNewChat creates a new conversation once the current has messages',
        () async {
      final _Rig rig = _Rig();
      final String first = await rig.active();
      await rig.chatReady(first);
      rig.container.read(chatNotifierProvider(first).notifier).send('hello');

      await rig.controller.startNewChat();
      final String second = await rig.active();
      expect(second, isNot(first));
      expect(rig.repo.conversations.keys, containsAll(<String>[first, second]));
    });
  });

  group('onMessageSent', () {
    test('titles an untitled conversation', () async {
      final _Rig rig = _Rig();
      final String id = await rig.active();
      await rig.controller.onMessageSent(id, '  مرحبا   كيف الحال  ');
      expect(rig.repo.conversations[id]!.title, 'مرحبا كيف الحال');
    });

    test('never overwrites an existing title', () async {
      final _Rig rig = _Rig();
      rig.repo.conversations['a'] = _conv('a', title: 'Keep me');
      final String id = await rig.active();
      await rig.controller.onMessageSent(id, 'something else');
      expect(rig.repo.conversations['a']!.title, 'Keep me');
    });

    test('ignores blank text and unknown conversations', () async {
      final _Rig rig = _Rig();
      final String id = await rig.active();
      await rig.controller.onMessageSent(id, '   ');
      expect(rig.repo.conversations[id]!.title, isEmpty);
      await rig.controller.onMessageSent('ghost', 'hello');
      expect(rig.repo.conversations.keys, <String>[id]);
    });
  });
}
