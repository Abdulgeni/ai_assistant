import 'dart:async';
import 'dart:math' as math;

import 'package:ai_assistant/domain/chat_repository.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/llm_client.dart';

/// One call to [FakeLlmClient.streamChat], driven by the test.
class FakeLlmCall {
  FakeLlmCall(this.request) {
    controller = StreamController<StreamEvent>(
      onCancel: () {
        cancelled = true;
      },
    );
  }

  final ChatRequest request;
  late final StreamController<StreamEvent> controller;
  bool cancelled = false;

  void emit(StreamEvent event) => controller.add(event);

  /// Emits [terminal] and closes, as a contract-abiding client does.
  Future<void> finish([StreamEvent terminal = const DoneEvent()]) async {
    controller.add(terminal);
    await controller.close();
  }

  /// Violates the contract on purpose: closes with no terminal event.
  Future<void> closeWithoutTerminal() => controller.close();

  /// Violates the contract on purpose: errors the stream.
  void failWithStreamError() => controller.addError(StateError('boom'));
}

class FakeLlmClient implements LlmClient {
  final List<FakeLlmCall> calls = <FakeLlmCall>[];

  FakeLlmCall get last => calls.last;

  @override
  Stream<StreamEvent> streamChat(ChatRequest request) {
    final FakeLlmCall call = FakeLlmCall(request);
    calls.add(call);
    return call.controller.stream;
  }
}

Duration _noDelay(ChatMessage message) => Duration.zero;

/// In-memory [ChatRepository] that records every write in order.
class InMemoryChatRepository implements ChatRepository {
  final Map<String, Conversation> conversations = <String, Conversation>{};
  final List<ChatMessage> messages = <ChatMessage>[];

  /// `save:<id>:<status>` and `delete:<id>`, appended when the write COMPLETES.
  final List<String> ops = <String>[];

  Duration Function(ChatMessage message) delayFor = _noDelay;
  bool failSaves = false;
  int recoverCalls = 0;

  ChatMessage? byId(String id) {
    for (final ChatMessage m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Stream<List<Conversation>> watchConversations() {
    final List<Conversation> sorted = conversations.values.toList()
      ..sort((Conversation a, Conversation b) => b.updatedAt.compareTo(a.updatedAt));
    return Stream<List<Conversation>>.value(sorted);
  }

  @override
  Future<void> saveConversation(Conversation conversation) async {
    conversations[conversation.id] = conversation;
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    conversations.remove(conversationId);
    messages.removeWhere((ChatMessage m) => m.conversationId == conversationId);
  }

  @override
  Future<void> renameConversation(String conversationId, String title) async {
    final Conversation? existing = conversations[conversationId];
    if (existing == null) return;
    conversations[conversationId] = Conversation(
      id: existing.id,
      title: title,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
    );
  }

  @override
  Future<List<ChatMessage>> loadMessages(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
  }) async {
    final List<ChatMessage> all = messages
        .where((ChatMessage m) => m.conversationId == conversationId)
        .toList();
    var end = all.length;
    if (beforeMessageId != null) {
      final int index =
          all.indexWhere((ChatMessage m) => m.id == beforeMessageId);
      if (index < 0) return const <ChatMessage>[];
      end = index;
    }
    return all.sublist(math.max(0, end - limit), end);
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    await Future<void>.delayed(delayFor(message));
    if (failSaves) throw StateError('disk full');
    ops.add('save:${message.id}:${message.status.name}');
    final int index = messages.indexWhere((ChatMessage m) => m.id == message.id);
    if (index >= 0) {
      messages[index] = message;
    } else {
      messages.add(message);
    }
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    ops.add('delete:$messageId');
    messages.removeWhere((ChatMessage m) => m.id == messageId);
  }

  @override
  Future<int> recoverInterruptedStreams() async {
    recoverCalls++;
    var fixed = 0;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].status == MessageStatus.streaming) {
        messages[i] = messages[i].copyWith(status: MessageStatus.failed);
        fixed++;
      }
    }
    return fixed;
  }

  @override
  Future<List<ChatMessage>> searchMessages(String query, {int limit = 50}) async =>
      const <ChatMessage>[];
}
