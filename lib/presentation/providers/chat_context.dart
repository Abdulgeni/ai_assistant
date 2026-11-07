import 'package:ai_assistant/domain/entities/chat_message.dart';

/// Chooses which messages are sent to the model.
///
///  * Only user/system messages and COMPLETED assistant answers are eligible:
///    a failed, cancelled, or streaming assistant message is noise.
///  * Newest messages win: walk backward until [maxMessages] or [maxChars] is
///    reached. The newest eligible message is always included, even if it
///    alone exceeds the budget.
///  * The result never starts with an assistant message.
///
/// [maxChars] is a rough stand-in for a token budget (Arabic usually costs more
/// tokens per character than English, so keep it conservative).
List<ChatMessage> selectContext(
  List<ChatMessage> messages, {
  int maxMessages = 40,
  int maxChars = 24000,
}) {
  final List<ChatMessage> eligible = <ChatMessage>[
    for (final ChatMessage message in messages)
      if (message.role != ChatRole.assistant ||
          message.status == MessageStatus.complete)
        message,
  ];

  final List<ChatMessage> picked = <ChatMessage>[];
  var chars = 0;
  for (var i = eligible.length - 1; i >= 0; i--) {
    final ChatMessage message = eligible[i];
    final bool isNewest = picked.isEmpty;
    if (!isNewest &&
        (picked.length >= maxMessages ||
            chars + message.content.length > maxChars)) {
      break;
    }
    picked.add(message);
    chars += message.content.length;
  }

  final List<ChatMessage> chronological = picked.reversed.toList();
  var start = 0;
  while (start < chronological.length &&
      chronological[start].role == ChatRole.assistant) {
    start++;
  }
  return chronological.sublist(start);
}
