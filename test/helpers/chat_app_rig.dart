import 'package:ai_assistant/app.dart';
import 'package:ai_assistant/core/config/app_config.dart';
import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_test_doubles.dart';
import 'fake_platform_actions.dart';

/// The whole app on fakes. Seed conversations and messages BEFORE [pump]; the
/// most recently updated conversation opens first.
class ChatAppRig {
  ChatAppRig({this.locale = const Locale('ar')}) {
    container = ProviderContainer(
      overrides: <Override>[
        chatRepositoryProvider.overrideWithValue(repo),
        llmClientProvider.overrideWithValue(llm),
        platformActionsProvider.overrideWithValue(platform),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            gatewayBaseUrl: 'https://gateway.test',
            devAuthToken: 't',
          ),
        ),
        clockProvider.overrideWithValue(
          () => DateTime(2026, 3, 1, 12).add(Duration(seconds: _tick++)),
        ),
        idGeneratorProvider.overrideWithValue(() => 'id${++_id}'),
        streamingFlushIntervalProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(container.dispose);
  }

  final Locale locale;
  final FakeLlmClient llm = FakeLlmClient();
  final InMemoryChatRepository repo = InMemoryChatRepository();
  final FakePlatformActions platform = FakePlatformActions();
  late final ProviderContainer container;
  int _id = 0;
  int _tick = 0;

  AppLocalizations get l10n => lookupAppLocalizations(locale);

  void addConversation(String id, {String title = '', int updated = 0}) {
    repo.conversations[id] = Conversation(
      id: id,
      title: title,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026).add(Duration(seconds: updated)),
    );
  }

  void addMessage(
    String id,
    String conversationId,
    ChatRole role,
    String content, {
    MessageStatus status = MessageStatus.complete,
    List<SourceReference> sources = const <SourceReference>[],
  }) {
    repo.messages.add(
      ChatMessage(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content,
        createdAt: DateTime(2026),
        status: status,
        sources: sources,
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AppRoot()),
    );
    container.read(localeProvider.notifier).setLocale(locale);
    await settle(tester);
  }

  /// Loops (skeleton, caret, thinking dots) never settle, so advance by time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    container.dispose();
  }
}
