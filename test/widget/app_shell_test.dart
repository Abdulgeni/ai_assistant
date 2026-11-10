import 'package:ai_assistant/app.dart';
import 'package:ai_assistant/core/config/app_config.dart';
import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/providers/streaming_buffer.dart';
import 'package:ai_assistant/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_doubles.dart';

const String _arTitle = 'المساعد الذكي';
const String _enTitle = 'AI Assistant';

/// Skeleton and thinking loops never settle, so tests advance time with `pump`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<ProviderContainer> _pumpApp(WidgetTester tester, {Locale? locale}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      chatRepositoryProvider.overrideWithValue(InMemoryChatRepository()),
      llmClientProvider.overrideWithValue(FakeLlmClient()),
      appConfigProvider.overrideWithValue(
        const AppConfig(gatewayBaseUrl: 'https://gateway.test', devAuthToken: 't'),
      ),
      streamingFlushIntervalProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AppRoot()),
  );
  if (locale != null) {
    container.read(localeProvider.notifier).setLocale(locale);
  }
  await _settle(tester);
  return container;
}

TextDirection _direction(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(ChatScreen)));

void main() {
  testWidgets('Arabic locale: RTL layout with Arabic strings',
      (WidgetTester tester) async {
    await _pumpApp(tester, locale: const Locale('ar'));
    expect(_direction(tester), TextDirection.rtl);
    expect(find.text(_arTitle), findsOneWidget);
  });

  testWidgets('English locale: LTR layout with English strings',
      (WidgetTester tester) async {
    await _pumpApp(tester, locale: const Locale('en'));
    expect(_direction(tester), TextDirection.ltr);
    expect(find.text(_enTitle), findsOneWidget);
  });

  testWidgets('layout mirrors: the title hugs the start edge',
      (WidgetTester tester) async {
    await _pumpApp(tester, locale: const Locale('ar'));
    final double width = tester.getSize(find.byType(MaterialApp)).width;
    expect(tester.getTopRight(find.text(_arTitle)).dx, greaterThan(width / 2));

    await _pumpApp(tester, locale: const Locale('en'));
    expect(tester.getTopLeft(find.text(_enTitle)).dx, lessThan(width / 2));
  });

  testWidgets('unsupported device language falls back to Arabic',
      (WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await _pumpApp(tester);
    expect(find.text(_arTitle), findsOneWidget);
    expect(_direction(tester), TextDirection.rtl);
  });

  testWidgets('the language button switches locale and direction',
      (WidgetTester tester) async {
    await _pumpApp(tester, locale: const Locale('ar'));
    await tester.tap(find.byIcon(Icons.translate_rounded));
    await _settle(tester);
    expect(find.text(_enTitle), findsOneWidget);
    expect(_direction(tester), TextDirection.ltr);
  });

  testWidgets('the theme button switches brightness',
      (WidgetTester tester) async {
    await _pumpApp(tester, locale: const Locale('en'));
    final Brightness before =
        Theme.of(tester.element(find.byType(ChatScreen))).brightness;
    await tester.tap(find.byIcon(Icons.brightness_6_rounded));
    await _settle(tester);
    final Brightness after =
        Theme.of(tester.element(find.byType(ChatScreen))).brightness;
    expect(after, isNot(before));
  });

  testWidgets('delegates include GlobalWidgetsLocalizations (sets direction)',
      (WidgetTester tester) async {
    expect(
      AppLocalizations.localizationsDelegates,
      contains(GlobalWidgetsLocalizations.delegate),
    );
  });
}
