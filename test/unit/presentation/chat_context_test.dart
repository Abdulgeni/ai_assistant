import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/presentation/providers/chat_context.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _m(
  String id,
  ChatRole role,
  String content, {
  MessageStatus status = MessageStatus.complete,
}) =>
    ChatMessage(
      id: id,
      conversationId: 'c',
      role: role,
      content: content,
      createdAt: DateTime(2026),
      status: status,
    );

List<String> _ids(List<ChatMessage> messages) =>
    messages.map((ChatMessage m) => m.id).toList();

void main() {
  test('sends everything when it fits', () {
    final List<ChatMessage> all = <ChatMessage>[
      _m('1', ChatRole.user, 'a'),
      _m('2', ChatRole.assistant, 'b'),
      _m('3', ChatRole.user, 'c'),
    ];
    expect(_ids(selectContext(all)), <String>['1', '2', '3']);
  });

  test('excludes failed, cancelled, and streaming assistant messages', () {
    final List<ChatMessage> all = <ChatMessage>[
      _m('1', ChatRole.user, 'q1'),
      _m('2', ChatRole.assistant, 'x', status: MessageStatus.failed),
      _m('3', ChatRole.user, 'q2'),
      _m('4', ChatRole.assistant, 'y', status: MessageStatus.cancelled),
      _m('5', ChatRole.user, 'q3'),
      _m('6', ChatRole.assistant, '', status: MessageStatus.streaming),
    ];
    expect(_ids(selectContext(all)), <String>['1', '3', '5']);
  });

  test('keeps the newest messages within the character budget', () {
    final List<ChatMessage> all = <ChatMessage>[
      _m('1', ChatRole.user, 'aaaaaaaaaa'),
      _m('2', ChatRole.assistant, 'bbbbbbbbbb'),
      _m('3', ChatRole.user, 'cccccccccc'),
      _m('4', ChatRole.assistant, 'dddddddddd'),
      _m('5', ChatRole.user, 'eeeeeeeeee'),
    ];
    // Budget for three 10-char messages: 5, 4, 3 are picked; 3 is a user message.
    expect(_ids(selectContext(all, maxChars: 30)), <String>['3', '4', '5']);
  });

  test('never starts with an assistant message', () {
    final List<ChatMessage> all = <ChatMessage>[
      _m('1', ChatRole.user, 'aaaaaaaaaa'),
      _m('2', ChatRole.assistant, 'bbbbbbbbbb'),
      _m('3', ChatRole.user, 'cccccccccc'),
    ];
    // Budget fits messages 2 and 3, but 2 is an assistant turn and is dropped.
    expect(_ids(selectContext(all, maxChars: 20)), <String>['3']);
  });

  test('always includes the newest message, even over budget', () {
    final List<ChatMessage> all = <ChatMessage>[
      _m('1', ChatRole.user, 'a'),
      _m('2', ChatRole.assistant, 'b'),
      _m('3', ChatRole.user, 'x' * 1000),
    ];
    expect(_ids(selectContext(all, maxChars: 10)), <String>['3']);
  });

  test('respects maxMessages', () {
    final List<ChatMessage> all = <ChatMessage>[
      for (var i = 0; i < 10; i++)
        _m('$i', i.isEven ? ChatRole.user : ChatRole.assistant, 'x'),
    ];
    // Newest eligible is index 9 (assistant); picked 9,8,7,6 -> 6 is a user.
    expect(_ids(selectContext(all, maxMessages: 4)), <String>['6', '7', '8', '9']);
  });

  test('an empty conversation selects nothing', () {
    expect(selectContext(const <ChatMessage>[]), isEmpty);
  });

  test('counts Arabic by characters', () {
    final List<ChatMessage> all = <ChatMessage>[
      _m('1', ChatRole.user, 'مرحبا بالعالم'),
    ];
    expect(_ids(selectContext(all, maxChars: 5)), <String>['1']);
  });
}
