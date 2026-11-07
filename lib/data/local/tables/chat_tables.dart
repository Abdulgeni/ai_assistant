import 'package:drift/drift.dart';

/// Conversation list.
///
/// Drift stores [DateTime] as whole seconds by default, so never order messages
/// by timestamp; order by `ChatMessages.seq` (insertion order).
@DataClassName('ConversationRow')
@TableIndex(name: 'idx_conversations_updated_at', columns: {#updatedAt})
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Chat messages.
///
/// * `seq` is the stable integer key (insertion order, and the FTS5 rowid).
///   `VACUUM` may renumber rowids of tables without an INTEGER PRIMARY KEY,
///   which would corrupt the external-content FTS index.
/// * `id` is the domain id (uuid).
/// * `role` / `status` hold enum names (`ChatRole.name`, `MessageStatus.name`);
///   the repository maps them with `byName`.
/// * `isCommitted` MUST equal `status != 'streaming'` (the repository mapper is
///   the only writer and enforces this).
/// * `searchText` is `normalizeForSearch(content)`; the FTS index reads it.
@DataClassName('ChatMessageRow')
@TableIndex(
  name: 'idx_chat_messages_conversation_seq',
  columns: {#conversationId, #seq},
)
class ChatMessages extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get id => text().unique()();
  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get searchText => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get status => text()();
  BoolColumn get isCommitted => boolean().withDefault(const Constant(true))();

  /// JSON-encoded list of `SourceReference`s, or null.
  TextColumn get sourcesJson => text().nullable()();
}
