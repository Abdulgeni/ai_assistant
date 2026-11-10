import 'package:ai_assistant/app.dart';
import 'package:ai_assistant/core/config/app_config.dart';
import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_bubble.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_doubles.dart';

final AppLocalizations _ar = lookupAppLocalizations(const Locale('ar'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

class _App {
  _App({bool configured = true, this.locale = const Locale('ar')}) {
    container = ProviderContainer(
      overrides: <Override>[
        chatRepositoryProvider.overrideWithValue(repo),
        llmClientProvider.overrideWithValue(llm),
        appConfigProvider.overrideWithValue(
          AppConfig(
            gatewayBaseUrl: configured ? 'https://gateway.test' : '',
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
  late final ProviderContainer container;
  int _id = 0;
  int _tick = 0;

  AppLocalizations get l10n => lookupAppLocalizations(locale);

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

  /// Disposes the widget tree AND the provider container so any pending
  /// animation timers and notifier subscriptions are released before the
  /// test ends. Without this, `flutter_test` throws
  /// "A Timer is still pending even after the widget tree was disposed".
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Give pending microtasks (stream cancellations, timers) a moment.
    await tester.pump(const Duration(milliseconds: 50));
    container.dispose();
  }

  void seed(int count) {
    repo.conversations['c1'] = Conversation(
      id: 'c1',
      title: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    for (var i = 0; i < count; i++) {
      repo.messages.add(
        ChatMessage(
          id: 'h${i.toString().padLeft(3, '0')}',
          conversationId: 'c1',
          role: i.isEven ? ChatRole.user : ChatRole.assistant,
          content: 'history message number $i with some extra words to fill space',
          createdAt: DateTime(2026),
        ),
      );
    }
  }
}

void main() {
  testWidgets('empty state: RTL, Arabic greeting, suggestions',
      (WidgetTester tester) async {
    final _App app = _App();
    await app.pump(tester);
    expect(find.text(_ar.emptyTitle), findsOneWidget);
    expect(find.text(_ar.suggestionSummarize), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(_ar.emptyTitle))),
      TextDirection.rtl,
    );
    await app.dispose(tester);
  });

  testWidgets('tapping a suggestion sends it and shows the thinking state',
      (WidgetTester tester) async {
    final _App app = _App();
    await app.pump(tester);
    await tester.tap(find.text(_ar.suggestionEmail));
    await app.settle(tester);

    expect(find.text(_ar.suggestionEmail), findsOneWidget);
    expect(find.byType(ThinkingIndicator), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(app.llm.calls, hasLength(1));
    await app.dispose(tester);
  });

  testWidgets('streamed tokens appear, and finishing restores the send button',
      (WidgetTester tester) async {
    final _App app = _App();
    await app.pump(tester);
    await tester.tap(find.text(_ar.suggestionExplain));
    await app.settle(tester);

    app.llm.last
      ..emit(const TokenEvent('أهلًا'))
      ..emit(const TokenEvent(' بك'));
    await app.settle(tester);
    expect(find.textContaining('أهلًا بك', findRichText: true), findsOneWidget);
    expect(find.byType(ThinkingIndicator), findsNothing);

    await app.llm.last.finish();
    await app.settle(tester);
    expect(find.text('أهلًا بك'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('typing and sending clears the field and shows the message',
      (WidgetTester tester) async {
    final _App app = _App(locale: const Locale('en'));
    await app.pump(tester);
    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await app.settle(tester);

    expect(find.text('hello there'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await app.dispose(tester);
  });

  testWidgets('a failed reply shows the localized error, and Retry restarts it',
      (WidgetTester tester) async {
    final _App app = _App();
    await app.pump(tester);
    await tester.tap(find.text(_ar.suggestionSummarize));
    await app.settle(tester);

    await app.llm.last.finish(
      const ErrorEvent(
        StreamFailure(code: StreamFailureCode.rateLimited, message: 'x'),
      ),
    );
    await app.settle(tester);
    expect(find.text(_ar.errorRateLimited), findsOneWidget);
    expect(find.text(_ar.retry), findsOneWidget);

    await tester.tap(find.text(_ar.retry));
    await app.settle(tester);
    expect(app.llm.calls, hasLength(2));
    expect(find.text(_ar.errorRateLimited), findsNothing);
    await app.dispose(tester);
  });

  testWidgets('stop cancels the request and marks the message stopped',
      (WidgetTester tester) async {
    final _App app = _App();
    await app.pump(tester);
    await tester.tap(find.text(_ar.suggestionSummarize));
    await app.settle(tester);
    app.llm.last.emit(const TokenEvent('partial'));
    await app.settle(tester);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await app.settle(tester);
    expect(app.llm.last.cancelled, isTrue);
    expect(find.text(_ar.messageStopped), findsOneWidget);
    expect(find.text('partial'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('an unconfigured app shows a notice and sends nothing',
      (WidgetTester tester) async {
    final _App app = _App(configured: false);
    await app.pump(tester);
    expect(find.text(_ar.notConfigured), findsOneWidget);

    await tester.tap(find.text(_ar.suggestionEmail));
    await app.settle(tester);
    expect(app.llm.calls, isEmpty);
    await app.dispose(tester);
  });

  testWidgets('bubbles align by sender and mirror with the UI direction',
      (WidgetTester tester) async {
    for (final Locale locale in const <Locale>[Locale('en'), Locale('ar')]) {
      final _App app = _App(locale: locale);
      await app.pump(tester);
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await app.settle(tester);

      final double width = tester.getSize(find.byType(MaterialApp)).width;
      final Finder bubbleText = find.text('hi');
      if (locale.languageCode == 'en') {
        expect(tester.getTopRight(bubbleText).dx, greaterThan(width / 2));
      } else {
        expect(tester.getTopLeft(bubbleText).dx, lessThan(width / 2));
      }
      await app.dispose(tester);
    }
  });

  testWidgets('"jump to latest" appears after scrolling up and returns to the bottom',
      (WidgetTester tester) async {
    final _App app = _App();
    app.seed(40);
    await app.pump(tester);

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byKey(MessageList.jumpButtonKey)).opacity;

    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await app.settle(tester);
    expect(opacity(), 1);

    await tester.tap(find.byIcon(Icons.arrow_downward_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(), 0);
    await app.dispose(tester);
  });

  testWidgets('the send button is exposed to assistive technology',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final _App app = _App();
    await app.pump(tester);
    expect(find.bySemanticsLabel(_ar.send), findsOneWidget);
    expect(find.bySemanticsLabel(_ar.newChat), findsOneWidget);
    handle.dispose();
    await app.dispose(tester);
  });

  testWidgets('no overflow at 2x text on a small screen with a failed reply',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final _App app = _App();
    await app.pump(tester);
    expect(tester.takeException(), isNull);

    // Type a message instead of tapping a suggestion: at 2x text scale on a
    // 360x640 screen the suggestion chips can scroll off the visible area,
    // so a tap would miss. The composer is always on-screen.
    await tester.enterText(find.byType(TextField), 'overflow probe');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await app.settle(tester);
    expect(app.llm.calls, hasLength(1));
    await app.llm.last.finish(
      const ErrorEvent(
        StreamFailure(code: StreamFailureCode.network, message: 'x'),
      ),
    );
    await app.settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(_en.appTitle), findsNothing);
    await app.dispose(tester);
  });
}
