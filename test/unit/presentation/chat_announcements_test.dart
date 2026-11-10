import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/presentation/a11y/chat_announcements.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

ChatMessage _assistant(String id, MessageStatus status) => ChatMessage(
      id: id,
      conversationId: 'c',
      role: ChatRole.assistant,
      content: 'x',
      createdAt: DateTime(2026),
      status: status,
    );

ChatState _state({
  String? streaming,
  List<ChatMessage> messages = const <ChatMessage>[],
  StreamFailure? failure,
}) =>
    ChatState(
      status: ChatLoadStatus.ready,
      messages: messages,
      streamingMessageId: streaming,
      failure: failure,
    );

String? _announce(ChatState? previous, ChatState next) =>
    announcementFor(previous: previous, next: next, l10n: _l10n);

void main() {
  final ChatState streaming = _state(
    streaming: 'a',
    messages: <ChatMessage>[_assistant('a', MessageStatus.streaming)],
  );

  test('a reply starting announces "thinking"', () {
    expect(_announce(_state(), streaming), _l10n.thinking);
    expect(_announce(null, streaming), _l10n.thinking);
  });

  test('a reply completing announces "response ready"', () {
    expect(
      _announce(
        streaming,
        _state(messages: <ChatMessage>[_assistant('a', MessageStatus.complete)]),
      ),
      _l10n.responseReady,
    );
  });

  test('a failure announces the localized error', () {
    expect(
      _announce(
        streaming,
        _state(
          messages: <ChatMessage>[_assistant('a', MessageStatus.failed)],
          failure: const StreamFailure(
            code: StreamFailureCode.network,
            message: 'x',
          ),
        ),
      ),
      _l10n.errorNetwork,
    );
  });

  test('a failure without detail announces the generic message', () {
    expect(
      _announce(
        streaming,
        _state(messages: <ChatMessage>[_assistant('a', MessageStatus.failed)]),
      ),
      _l10n.messageFailed,
    );
  });

  test('stopping announces "stopped", with or without partial text', () {
    expect(
      _announce(
        streaming,
        _state(messages: <ChatMessage>[_assistant('a', MessageStatus.cancelled)]),
      ),
      _l10n.messageStopped,
    );
    expect(_announce(streaming, _state()), _l10n.messageStopped);
  });

  test('nothing is announced while streaming continues or when idle', () {
    expect(_announce(streaming, streaming), isNull);
    expect(_announce(_state(), _state()), isNull);
    expect(_announce(null, _state()), isNull);
  });
}
