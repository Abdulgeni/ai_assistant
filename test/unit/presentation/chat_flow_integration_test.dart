import 'package:ai_assistant/data/local/app_database.dart';
import 'package:ai_assistant/data/repositories/chat_repository_impl.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_doubles.dart';

/// The notifier on the REAL Drift repository (in-memory database).
void main() {
  late AppDatabase db;
  late ChatRepositoryImpl repo;
  late int ids;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    repo = ChatRepositoryImpl(db);
    await repo.saveConversation(
      Conversation(
        id: 'c1',
        title: '',
        createdAt: DateTime(2026, 3, 1, 12),
        updatedAt: DateTime(2026, 3, 1, 12),
      ),
    );
    ids = 0;
  });

  ProviderContainer boot(FakeLlmClient llm) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        llmClientProvider.overrideWithValue(llm),
        chatRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 1, 12, 0, ids)),
        idGeneratorProvider.overrideWithValue(() => 'id${++ids}'),
        streamingFlushIntervalProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> ready(ProviderContainer container) async {
    container.read(chatNotifierProvider('c1'));
    for (var i = 0;
        i < 100 &&
            container.read(chatNotifierProvider('c1')).status ==
                ChatLoadStatus.loading;
        i++) {
      await pumpEventQueue(times: 5);
    }
  }

  test('a finished reply survives a restart, with Arabic text and sources',
      () async {
    final FakeLlmClient llm = FakeLlmClient();
    final ProviderContainer first = boot(llm);
    await ready(first);
    first.read(chatNotifierProvider('c1').notifier).send('مرحبا');
    final FakeLlmCall call = llm.last;
    call
      ..emit(SourcesEvent(const <SourceReference>[
        SourceReference(id: 's1', title: 'مستند'),
      ]))
      ..emit(const TokenEvent('أهلًا'))
      ..emit(const TokenEvent(' بك'));
    await call.finish();
    await pumpEventQueue();
    await first.read(chatNotifierProvider('c1').notifier).flushWrites();

    // "Restart": a brand-new container over the same database.
    final ProviderContainer second = boot(FakeLlmClient());
    await ready(second);
    final List<ChatMessage> messages =
        second.read(chatNotifierProvider('c1')).messages;
    expect(messages.map((ChatMessage m) => m.content), <String>['مرحبا', 'أهلًا بك']);
    expect(messages.last.status, MessageStatus.complete);
    expect(messages.last.sources.single.title, 'مستند');
  });

  test('a crash mid-reply comes back as a failed message after restart',
      () async {
    final FakeLlmClient llm = FakeLlmClient();
    final ProviderContainer first = boot(llm);
    await ready(first);
    first.read(chatNotifierProvider('c1').notifier).send('question');
    llm.last.emit(const TokenEvent('partial'));
    await pumpEventQueue();
    await first.read(chatNotifierProvider('c1').notifier).flushWrites();
    // The app is killed here: the reply never finishes.

    final ProviderContainer second = boot(FakeLlmClient());
    await ready(second);
    final List<ChatMessage> messages =
        second.read(chatNotifierProvider('c1')).messages;
    expect(messages.map((ChatMessage m) => m.role), <ChatRole>[
      ChatRole.user,
      ChatRole.assistant,
    ]);
    expect(messages.last.status, MessageStatus.failed);

    // And the user can retry it.
    final FakeLlmClient llm2 = FakeLlmClient();
    final ProviderContainer third = boot(llm2);
    await ready(third);
    expect(third.read(chatNotifierProvider('c1').notifier).regenerate(), isTrue);
    expect(llm2.last.request.messages.single.content, 'question');
  });
}
