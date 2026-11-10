import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_app_rig.dart';

ChatAppRig _rigWithTwoChats() {
  final ChatAppRig rig = ChatAppRig();
  rig.addConversation('c1', title: 'Recipes', updated: 20);
  rig.addMessage('m1', 'c1', ChatRole.user, 'about recipes');
  rig.addConversation('c2', title: 'Travel plans', updated: 10);
  rig.addMessage('m2', 'c2', ChatRole.user, 'about travel');
  rig.addConversation('c3', updated: 5); // untitled
  return rig;
}

void main() {
  testWidgets('lists conversations, most recent first, untitled as "new chat"',
      (WidgetTester tester) async {
    final ChatAppRig rig = _rigWithTwoChats();
    await rig.pump(tester);
    await rig.openDrawer(tester);

    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Travel plans'), findsOneWidget);
    // One "new chat" for the untitled conversation (the app-bar and drawer
    // buttons carry it only as a semantics label).
    expect(find.text(rig.l10n.newChat), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Recipes')).dy,
      lessThan(tester.getTopLeft(find.text('Travel plans')).dy),
    );
    await rig.dispose(tester);
  });

  testWidgets('the most recent conversation opens first',
      (WidgetTester tester) async {
    final ChatAppRig rig = _rigWithTwoChats();
    await rig.pump(tester);
    expect(find.text('about recipes'), findsOneWidget);
    expect(find.text('about travel'), findsNothing);
    await rig.dispose(tester);
  });

  testWidgets('tapping another conversation opens it and closes the drawer',
      (WidgetTester tester) async {
    final ChatAppRig rig = _rigWithTwoChats();
    await rig.pump(tester);
    await rig.openDrawer(tester);

    await tester.tap(find.text('Travel plans'));
    await rig.settle(tester);
    await rig.settle(tester);

    expect(find.text('about travel'), findsOneWidget);
    expect(find.text('about recipes'), findsNothing);
    expect(find.text(rig.l10n.conversations), findsNothing);
    await rig.dispose(tester);
  });

  testWidgets('deleting asks first; cancelling keeps the conversation',
      (WidgetTester tester) async {
    final ChatAppRig rig = _rigWithTwoChats();
    await rig.pump(tester);
    await rig.openDrawer(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(1));
    await rig.settle(tester);
    expect(find.text(rig.l10n.deleteChatTitle), findsOneWidget);

    await tester.tap(find.text(rig.l10n.cancel));
    await rig.settle(tester);
    expect(rig.repo.conversations.keys, containsAll(<String>['c1', 'c2', 'c3']));
    await rig.dispose(tester);
  });

  testWidgets('confirming deletes the conversation and its messages',
      (WidgetTester tester) async {
    final ChatAppRig rig = _rigWithTwoChats();
    await rig.pump(tester);
    await rig.openDrawer(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(1)); // Travel
    await rig.settle(tester);
    await tester.tap(find.text(rig.l10n.delete));
    await rig.settle(tester);
    await rig.settle(tester);

    expect(rig.repo.conversations.containsKey('c2'), isFalse);
    expect(
      rig.repo.messages.where((ChatMessage m) => m.conversationId == 'c2'),
      isEmpty,
    );
    expect(find.text('Travel plans'), findsNothing);
    expect(find.text('Recipes'), findsOneWidget);
    await rig.dispose(tester);
  });

  testWidgets('deleting the open conversation switches to the next one',
      (WidgetTester tester) async {
    final ChatAppRig rig = _rigWithTwoChats();
    await rig.pump(tester);
    await rig.openDrawer(tester);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(0)); // Recipes (open)
    await rig.settle(tester);
    await tester.tap(find.text(rig.l10n.delete));
    await rig.settle(tester);
    await rig.settle(tester);

    expect(rig.repo.conversations.containsKey('c1'), isFalse);
    expect(find.text('about travel'), findsOneWidget);
    await rig.dispose(tester);
  });

  testWidgets('deleting a conversation that is streaming stops the reply',
      (WidgetTester tester) async {
    final ChatAppRig rig = ChatAppRig();
    rig.addConversation('c1', title: 'Busy', updated: 20);
    rig.addConversation('c2', title: 'Other', updated: 10);
    await rig.pump(tester);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await rig.settle(tester);
    expect(rig.llm.calls, hasLength(1));

    await rig.openDrawer(tester);
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(0));
    await rig.settle(tester);
    await tester.tap(find.text(rig.l10n.delete));

    // The confirm dialog pops, then _confirmDelete awaits onConfirmed
    // which awaits stop() and the repo delete. On Windows the cancel
    // future can take many microtask ticks to resolve, so wait until
    // the observable state changes rather than guessing a tick count.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (!rig.repo.conversations.containsKey('c1')) break;
    }

    expect(rig.llm.last.cancelled, isTrue,
        reason: 'the reply must be cancelled');
    expect(rig.repo.conversations.containsKey('c1'), isFalse,
        reason: 'the conversation must be deleted');
    expect(
      rig.repo.messages.where((ChatMessage m) => m.conversationId == 'c1'),
      isEmpty,
    );
    await rig.dispose(tester);
  });
}
