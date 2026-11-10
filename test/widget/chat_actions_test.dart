import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/presentation/widgets/chat/message_bubble.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_app_rig.dart';

ChatAppRig _rigWithAnswer() {
  final ChatAppRig rig = ChatAppRig();
  rig.addConversation('c1', updated: 1);
  rig.addMessage('u1', 'c1', ChatRole.user, 'question');
  rig.addMessage('a1', 'c1', ChatRole.assistant, 'the answer');
  return rig;
}

void main() {
  group('long-press actions', () {
    testWidgets('offer copy, share, and regenerate on the newest answer',
        (WidgetTester tester) async {
      final ChatAppRig rig = _rigWithAnswer();
      await rig.pump(tester);
      await tester.longPress(find.textContaining('the answer', findRichText: true));
      await rig.settle(tester);

      expect(find.text(rig.l10n.copy), findsOneWidget);
      expect(find.text(rig.l10n.share), findsOneWidget);
      expect(find.text(rig.l10n.regenerate), findsOneWidget);
      await rig.dispose(tester);
    });

    testWidgets('copy puts the message on the clipboard and confirms',
        (WidgetTester tester) async {
      final ChatAppRig rig = _rigWithAnswer();
      await rig.pump(tester);
      await tester.longPress(find.textContaining('the answer', findRichText: true));
      await rig.settle(tester);
      await tester.tap(find.text(rig.l10n.copy));
      await rig.settle(tester);

      expect(rig.platform.copied, <String>['the answer']);
      expect(find.text(rig.l10n.copied), findsOneWidget);
      await rig.dispose(tester);
    });

    testWidgets('share hands the message to the share sheet',
        (WidgetTester tester) async {
      final ChatAppRig rig = _rigWithAnswer();
      await rig.pump(tester);
      await tester.longPress(find.textContaining('the answer', findRichText: true));
      await rig.settle(tester);
      await tester.tap(find.text(rig.l10n.share));
      await rig.settle(tester);
      expect(rig.platform.shared, <String>['the answer']);
      await rig.dispose(tester);
    });

    testWidgets('regenerate restarts the answer', (WidgetTester tester) async {
      final ChatAppRig rig = _rigWithAnswer();
      await rig.pump(tester);
      await tester.longPress(find.textContaining('the answer', findRichText: true));
      await rig.settle(tester);
      await tester.tap(find.text(rig.l10n.regenerate));
      await rig.settle(tester);

      expect(rig.llm.calls, hasLength(1));
      expect(find.byType(ThinkingIndicator), findsOneWidget);
      await rig.dispose(tester);
    });

    testWidgets('regenerate is offered only on the newest assistant message',
        (WidgetTester tester) async {
      final ChatAppRig rig = ChatAppRig();
      rig.addConversation('c1', updated: 1);
      rig.addMessage('u1', 'c1', ChatRole.user, 'q one');
      rig.addMessage('a1', 'c1', ChatRole.assistant, 'answer one');
      rig.addMessage('u2', 'c1', ChatRole.user, 'q two');
      rig.addMessage('a2', 'c1', ChatRole.assistant, 'answer two');
      await rig.pump(tester);

      await tester.longPress(find.textContaining('answer one', findRichText: true));
      await rig.settle(tester);
      expect(find.text(rig.l10n.copy), findsOneWidget);
      expect(find.text(rig.l10n.regenerate), findsNothing);

      await tester.tapAt(const Offset(10, 10));
      await rig.settle(tester);

      await tester.longPress(find.textContaining('answer two', findRichText: true));
      await rig.settle(tester);
      expect(find.text(rig.l10n.regenerate), findsOneWidget);
      await rig.dispose(tester);
    });

    testWidgets('a message that is still streaming has no long-press menu',
        (WidgetTester tester) async {
      final ChatAppRig rig = ChatAppRig();
      await rig.pump(tester);
      await tester.tap(find.text(rig.l10n.suggestionEmail));
      await rig.settle(tester);

      await tester.longPress(find.byType(ThinkingIndicator));
      await rig.settle(tester);
      expect(find.text(rig.l10n.copy), findsNothing);
      await rig.dispose(tester);
    });
  });

  group('sources', () {
    ChatAppRig rigWithSources() {
      final ChatAppRig rig = ChatAppRig();
      rig.addConversation('c1', updated: 1);
      rig.addMessage('u1', 'c1', ChatRole.user, 'question');
      rig.addMessage(
        'a1',
        'c1',
        ChatRole.assistant,
        'the answer',
        sources: const <SourceReference>[
          SourceReference(id: 's1', title: 'Doc one', uri: 'https://example.com/1'),
          SourceReference(id: 's2', title: 'Doc two', uri: 'javascript:alert(1)'),
        ],
      );
      return rig;
    }

    testWidgets('the chip lists the sources', (WidgetTester tester) async {
      final ChatAppRig rig = rigWithSources();
      await rig.pump(tester);
      await tester.tap(find.text(rig.l10n.sourcesCount(2)));
      await rig.settle(tester);

      expect(find.text(rig.l10n.sourcesTitle), findsOneWidget);
      expect(find.text('Doc one'), findsOneWidget);
      expect(find.text('Doc two'), findsOneWidget);
      await rig.dispose(tester);
    });

    testWidgets('a web source opens only after confirmation',
        (WidgetTester tester) async {
      final ChatAppRig rig = rigWithSources();
      await rig.pump(tester);
      await tester.tap(find.text(rig.l10n.sourcesCount(2)));
      await rig.settle(tester);

      await tester.tap(find.text('Doc one'));
      await rig.settle(tester);
      expect(find.text(rig.l10n.openLinkTitle), findsOneWidget);
      expect(rig.platform.opened, isEmpty);

      await tester.tap(find.text(rig.l10n.open));
      await rig.settle(tester);
      expect(rig.platform.opened, <Uri>[Uri.parse('https://example.com/1')]);
      await rig.dispose(tester);
    });

    testWidgets('a source with an unsafe link is listed but not openable',
        (WidgetTester tester) async {
      final ChatAppRig rig = rigWithSources();
      await rig.pump(tester);
      await tester.tap(find.text(rig.l10n.sourcesCount(2)));
      await rig.settle(tester);

      await tester.tap(find.text('Doc two'));
      await rig.settle(tester);
      expect(find.text(rig.l10n.openLinkTitle), findsNothing);
      expect(rig.platform.opened, isEmpty);
      await rig.dispose(tester);
    });
  });
}
