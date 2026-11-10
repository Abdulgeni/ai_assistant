import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/widgets/chat/code_block.dart';
import 'package:ai_assistant/presentation/widgets/chat/markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_platform_actions.dart';

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

Widget _host(
  FakePlatformActions platform,
  String markdown, {
  Locale locale = const Locale('en'),
}) =>
    ProviderScope(
      overrides: <Override>[platformActionsProvider.overrideWithValue(platform)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownContent(text: markdown, color: Colors.black),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders headings, emphasis, and lists', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        FakePlatformActions(),
        '# Title\n\nSome **bold** text.\n\n- first\n- second\n',
      ),
    );
    expect(find.text('Title', findRichText: true), findsOneWidget);
    expect(find.textContaining('bold', findRichText: true), findsOneWidget);
    expect(find.text('first', findRichText: true), findsOneWidget);
    expect(find.text('second', findRichText: true), findsOneWidget);
  });

  group('code', () {
    testWidgets('a fenced block becomes a CodeBlock with its language',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(FakePlatformActions(), 'Intro\n\n```dart\nprint(1);\n```\n'),
      );
      expect(find.byType(CodeBlock), findsOneWidget);
      expect(find.text('print(1);'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
    });

    testWidgets('a fenced block with no language is still a CodeBlock',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(FakePlatformActions(), '```\nplain code\n```\n'),
      );
      expect(find.byType(CodeBlock), findsOneWidget);
    });

    testWidgets('inline code is NOT a CodeBlock', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(FakePlatformActions(), 'Call `foo()` now.'),
      );
      expect(find.byType(CodeBlock), findsNothing);
      expect(find.textContaining('foo()', findRichText: true), findsOneWidget);
    });

    testWidgets('the copy button copies exactly the code and confirms briefly',
        (WidgetTester tester) async {
      final FakePlatformActions platform = FakePlatformActions();
      await tester.pumpWidget(
        _host(platform, '```dart\nprint(1);\nprint(2);\n```\n'),
      );

      await tester.tap(find.byIcon(Icons.content_copy_rounded));
      await tester.pump();
      expect(platform.copied, <String>['print(1);\nprint(2);']);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.byIcon(Icons.content_copy_rounded), findsOneWidget);
    });

    testWidgets('the code block stays left-to-right inside an Arabic UI',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          FakePlatformActions(),
          'مثال:\n\n```dart\nprint(1);\n```\n',
          locale: const Locale('ar'),
        ),
      );
      final Finder code = find.text('print(1);');
      expect(Directionality.of(tester.element(code)), TextDirection.ltr);
    });
  });

  group('links', () {
    testWidgets('a tap asks first, then opens on confirmation',
        (WidgetTester tester) async {
      final FakePlatformActions platform = FakePlatformActions();
      await tester.pumpWidget(
        _host(platform, '[docs](https://example.com/a)'),
      );
      await tester.tap(find.text('docs', findRichText: true));
      await tester.pumpAndSettle();

      expect(find.text(_en.openLinkTitle), findsOneWidget);
      expect(find.text('https://example.com/a'), findsOneWidget);
      expect(platform.opened, isEmpty);

      await tester.tap(find.text(_en.open));
      await tester.pumpAndSettle();
      expect(platform.opened, <Uri>[Uri.parse('https://example.com/a')]);
    });

    testWidgets('cancelling opens nothing', (WidgetTester tester) async {
      final FakePlatformActions platform = FakePlatformActions();
      await tester.pumpWidget(_host(platform, '[docs](https://example.com)'));
      await tester.tap(find.text('docs', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.cancel));
      await tester.pumpAndSettle();
      expect(platform.opened, isEmpty);
    });

    testWidgets('a javascript: link shows no dialog and opens nothing',
        (WidgetTester tester) async {
      final FakePlatformActions platform = FakePlatformActions();
      await tester.pumpWidget(_host(platform, '[click](javascript:alert(1))'));
      await tester.tap(find.text('click', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text(_en.openLinkTitle), findsNothing);
      expect(platform.opened, isEmpty);
    });
  });

  testWidgets('Arabic Markdown renders in an RTL block',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        FakePlatformActions(),
        'مرحبا **بك**\n\n- الأول\n- الثاني\n',
        locale: const Locale('ar'),
      ),
    );
    expect(find.text('الأول', findRichText: true), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('الأول', findRichText: true))),
      TextDirection.rtl,
    );
  });
}
