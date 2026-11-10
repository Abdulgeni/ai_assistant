import 'package:ai_assistant/core/text/search_normalizer.dart';
import 'package:ai_assistant/data/local/app_database.dart';
import 'package:ai_assistant/data/models/chat_mappers.dart';
import 'package:ai_assistant/domain/chat_repository.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:drift/drift.dart';

// Both statements are verified against SQLite in the module's SQL checks.
// FTS5 external-content index over chat_messages.search_text (see AppDatabase).
const String _ftsSearchSql = '''
SELECT m.* FROM chat_messages AS m
JOIN chat_messages_fts AS f ON f.rowid = m.seq
WHERE chat_messages_fts MATCH ?
ORDER BY rank, m.seq DESC
LIMIT ?''';

// The escape character must equal [likeEscapeCharacter] (a backslash).
const String _likeSearchSql = r'''
SELECT * FROM chat_messages
WHERE search_text LIKE ? ESCAPE '\'
ORDER BY seq DESC
LIMIT ?''';

/// [ChatRepository] on Drift/SQLite.
///
/// Notes:
///  * Drift stores [DateTime] as whole seconds, so timestamps lose sub-second
///    precision on a round trip, and come back as local time. Message order
///    never depends on timestamps; it uses the insertion sequence.
///  * Rows the app cannot interpret (unknown role) are skipped when reading.
final class ChatRepositoryImpl implements ChatRepository {
  /// [forceLikeSearch] is a test hook that bypasses the FTS index so both
  /// search paths can be exercised on the same database.
  ChatRepositoryImpl(this._db, {this.forceLikeSearch = false});

  final AppDatabase _db;
  final bool forceLikeSearch;

  @override
  Stream<List<Conversation>> watchConversations() {
    final query = _db.select(_db.conversations)
      ..orderBy(<OrderingTerm Function($ConversationsTable)>[
        (t) => OrderingTerm.desc(t.updatedAt),
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.id),
      ]);
    return query.watch().map(
          (List<ConversationRow> rows) =>
              rows.map(conversationFromRow).toList(growable: false),
        );
  }

  @override
  Future<void> saveConversation(Conversation conversation) async {
    await _db.into(_db.conversations).insertOnConflictUpdate(
          ConversationsCompanion(
            id: Value<String>(conversation.id),
            title: Value<String>(conversation.title),
            createdAt: Value<DateTime>(conversation.createdAt),
            updatedAt: Value<DateTime>(conversation.updatedAt),
          ),
        );
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    // ON DELETE CASCADE removes the messages; triggers keep the FTS index in
    // sync. Requires PRAGMA foreign_keys = ON (set in AppDatabase.beforeOpen).
    await (_db.delete(_db.conversations)
          ..where((t) => t.id.equals(conversationId)))
        .go();
  }

  @override
  Future<List<ChatMessage>> loadMessages(
    String conversationId, {
    int limit = 50,
    String? beforeMessageId,
  }) async {
    assert(limit > 0, 'limit must be positive');

    int? beforeSeq;
    if (beforeMessageId != null) {
      beforeSeq = await _seqOf(conversationId, beforeMessageId);
      // A cursor that no longer exists (deleted, or another conversation)
      // means there is nothing before it.
      if (beforeSeq == null) return const <ChatMessage>[];
    }
    final int? cursor = beforeSeq;

    final query = _db.select(_db.chatMessages)
      ..where((m) {
        final Expression<bool> inConversation =
            m.conversationId.equals(conversationId);
        return cursor == null
            ? inConversation
            : inConversation & m.seq.isSmallerThanValue(cursor);
      })
      ..orderBy(<OrderingTerm Function($ChatMessagesTable)>[
        (m) => OrderingTerm.desc(m.seq),
      ])
      ..limit(limit);

    final List<ChatMessageRow> newestFirst = await query.get();
    return _toMessages(newestFirst.reversed);
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    await _db.transaction(() async {
      final ConversationRow? conversation = await (_db.select(_db.conversations)
            ..where((t) => t.id.equals(message.conversationId)))
          .getSingleOrNull();
      if (conversation == null) {
        throw StateError(
          'Cannot save a message: conversation ${message.conversationId} '
          'does not exist.',
        );
      }

      final ChatMessagesCompanion row = chatMessageToCompanion(message);
      await _db.into(_db.chatMessages).insert(
            row,
            // Only the mutable columns change on conflict: seq, role,
            // conversation and createdAt stay as first written.
            onConflict: DoUpdate(
              (old) => ChatMessagesCompanion(
                content: row.content,
                searchText: row.searchText,
                status: row.status,
                isCommitted: row.isCommitted,
                sourcesJson: row.sourcesJson,
              ),
              target: <Column<Object>>[_db.chatMessages.id],
            ),
          );

      // Bump the conversation forward, never backward.
      await (_db.update(_db.conversations)
            ..where(
              (t) =>
                  t.id.equals(message.conversationId) &
                  t.updatedAt.isSmallerThanValue(message.createdAt),
            ))
          .write(
        ConversationsCompanion(updatedAt: Value<DateTime>(message.createdAt)),
      );
    });
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    await (_db.delete(_db.chatMessages)..where((m) => m.id.equals(messageId)))
        .go();
  }

  @override
  Future<void> renameConversation(String conversationId, String title) async {
    await (_db.update(_db.conversations)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsCompanion(title: Value<String>(title)));
  }

  @override
  Future<int> recoverInterruptedStreams() {
    // Either signal counts, so a row whose flag and status disagree is fixed.
    return (_db.update(_db.chatMessages)
          ..where(
            (m) =>
                m.isCommitted.equals(false) |
                m.status.equals(MessageStatus.streaming.name),
          ))
        .write(
      ChatMessagesCompanion(
        status: Value<String>(MessageStatus.failed.name),
        isCommitted: const Value<bool>(true),
      ),
    );
  }

  @override
  Future<List<ChatMessage>> searchMessages(String query, {int limit = 50}) async {
    assert(limit > 0, 'limit must be positive');

    final String? match = buildFtsMatchQuery(query);
    final List<ChatMessageRow> rows;
    if (match != null && _db.isFtsAvailable && !forceLikeSearch) {
      rows = await _runSearch(_ftsSearchSql, match, limit);
    } else {
      // Blank queries, terms under 3 characters, or no FTS index available.
      final String? pattern = buildLikePattern(query);
      if (pattern == null) return const <ChatMessage>[];
      rows = await _runSearch(_likeSearchSql, pattern, limit);
    }
    return _toMessages(rows);
  }

  Future<int?> _seqOf(String conversationId, String messageId) async {
    final ChatMessageRow? row = await (_db.select(_db.chatMessages)
          ..where(
            (m) => m.id.equals(messageId) & m.conversationId.equals(conversationId),
          ))
        .getSingleOrNull();
    return row?.seq;
  }

  Future<List<ChatMessageRow>> _runSearch(
    String sql,
    String term,
    int limit,
  ) async {
    final List<QueryRow> result = await _db.customSelect(
      sql,
      variables: <Variable<Object>>[
        Variable.withString(term),
        Variable.withInt(limit),
      ],
      readsFrom: {_db.chatMessages},
    ).get();
    return result
        .map((QueryRow row) => _db.chatMessages.map(row.data))
        .toList(growable: false);
  }

  List<ChatMessage> _toMessages(Iterable<ChatMessageRow> rows) => rows
      .map(tryChatMessageFromRow)
      .whereType<ChatMessage>()
      .toList(growable: false);
}
