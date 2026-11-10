import 'package:ai_assistant/domain/chat_repository.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:ai_assistant/presentation/providers/chat_notifier.dart';
import 'package:ai_assistant/presentation/providers/chat_state.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int _maxTitleLength = 40;

/// A chat title from the first message: first non-empty line, whitespace
/// collapsed, cut at [maxLength] characters (not UTF-16 units) with an
/// ellipsis. Empty for blank input.
String deriveTitle(String text, {int maxLength = _maxTitleLength}) {
  var firstLine = '';
  for (final String line in text.split(RegExp(r'[\r\n]+'))) {
    final String trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      firstLine = trimmed;
      break;
    }
  }
  final String collapsed = firstLine.replaceAll(RegExp(r'\s+'), ' ');
  final List<int> runes = collapsed.runes.toList();
  if (runes.length <= maxLength) return collapsed;
  return '${String.fromCharCodes(runes.take(maxLength)).trimRight()}…';
}

/// Which conversation the chat screen shows. Opens the most recently updated
/// one, or creates the first one.
class ActiveConversationController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final ChatRepository repo = ref.read(chatRepositoryProvider);
    final List<Conversation> existing = await repo.watchConversations().first;
    return existing.isEmpty ? _create(repo) : existing.first.id;
  }

  /// Switches to a fresh conversation, unless the current one is still empty
  /// (so repeated taps do not pile up blank chats).
  Future<void> startNewChat() async {
    final String? current = state.valueOrNull;
    if (current != null) {
      final ChatState chat = ref.read(chatNotifierProvider(current));
      if (chat.status == ChatLoadStatus.ready && chat.messages.isEmpty) return;
    }
    final String id = await _create(ref.read(chatRepositoryProvider));
    state = AsyncData<String>(id);
  }

  /// Titles an untitled conversation from its first message. Never overwrites
  /// an existing title.
  Future<void> onMessageSent(String conversationId, String text) async {
    final String title = deriveTitle(text);
    if (title.isEmpty) return;
    final ChatRepository repo = ref.read(chatRepositoryProvider);
    final List<Conversation> all = await repo.watchConversations().first;
    for (final Conversation conversation in all) {
      if (conversation.id == conversationId) {
        if (conversation.title.isEmpty) {
          await repo.renameConversation(conversationId, title);
        }
        return;
      }
    }
  }

  Future<String> _create(ChatRepository repo) async {
    final String id = ref.read(idGeneratorProvider)();
    final DateTime now = ref.read(clockProvider)();
    await repo.saveConversation(
      Conversation(id: id, title: '', createdAt: now, updatedAt: now),
    );
    return id;
  }
}

final activeConversationProvider =
    AsyncNotifierProvider<ActiveConversationController, String>(
  ActiveConversationController.new,
);
