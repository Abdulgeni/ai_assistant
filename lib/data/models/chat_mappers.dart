import 'dart:convert';

import 'package:ai_assistant/core/text/search_normalizer.dart';
import 'package:ai_assistant/data/local/app_database.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:drift/drift.dart';

Conversation conversationFromRow(ConversationRow row) => Conversation(
      id: row.id,
      title: row.title,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );

/// Maps a stored row to a domain message, or null when the row is unreadable
/// (unknown role, e.g. written by a newer app version). An unknown status
/// becomes [MessageStatus.failed] so the message is still shown.
ChatMessage? tryChatMessageFromRow(ChatMessageRow row) {
  final ChatRole? role = ChatRole.values.asNameMap()[row.role];
  if (role == null) return null;
  return ChatMessage(
    id: row.id,
    conversationId: row.conversationId,
    role: role,
    content: row.content,
    createdAt: row.createdAt,
    status: MessageStatus.values.asNameMap()[row.status] ?? MessageStatus.failed,
    sources: decodeSources(row.sourcesJson),
  );
}

/// Full-row companion for inserting a message.
///
/// The ONLY place that writes `isCommitted`: it is derived from the status, so
/// the two columns cannot disagree.
ChatMessagesCompanion chatMessageToCompanion(ChatMessage message) =>
    ChatMessagesCompanion(
      id: Value<String>(message.id),
      conversationId: Value<String>(message.conversationId),
      role: Value<String>(message.role.name),
      content: Value<String>(message.content),
      searchText: Value<String>(normalizeForSearch(message.content)),
      createdAt: Value<DateTime>(message.createdAt),
      status: Value<String>(message.status.name),
      isCommitted: Value<bool>(message.isCommitted),
      sourcesJson: Value<String?>(encodeSources(message.sources)),
    );

/// JSON for the `sources_json` column, or null when there are no sources.
String? encodeSources(List<SourceReference> sources) {
  if (sources.isEmpty) return null;
  return jsonEncode(<Map<String, String>>[
    for (final SourceReference source in sources)
      <String, String>{
        'id': source.id,
        'title': source.title,
        if (source.uri != null) 'uri': source.uri!,
        if (source.snippet != null) 'snippet': source.snippet!,
      },
  ]);
}

/// Tolerant inverse of [encodeSources]: anything unreadable yields fewer (or no)
/// sources instead of an exception.
List<SourceReference> decodeSources(String? json) {
  if (json == null || json.isEmpty) return const <SourceReference>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const <SourceReference>[];
  }
  if (decoded is! List<Object?>) return const <SourceReference>[];
  return decoded
      .map(_sourceFrom)
      .whereType<SourceReference>()
      .toList(growable: false);
}

SourceReference? _sourceFrom(Object? entry) {
  if (entry is! Map<String, Object?>) return null;
  final Object? id = entry['id'];
  final Object? title = entry['title'];
  if (id is! String || title is! String) return null;
  final Object? uri = entry['uri'];
  final Object? snippet = entry['snippet'];
  return SourceReference(
    id: id,
    title: title,
    uri: uri is String ? uri : null,
    snippet: snippet is String ? snippet : null,
  );
}
