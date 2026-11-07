import 'package:ai_assistant/data/local/tables/chat_tables.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Conversations, ChatMessages])
class AppDatabase extends _$AppDatabase {
  /// Production database (stored by drift_flutter as `ai_assistant.sqlite`).
  AppDatabase() : super(driftDatabase(name: 'ai_assistant'));

  /// For tests: pass `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.executor);

  bool _ftsAvailable = false;
  String? _ftsUnavailableReason;

  /// True when the FTS5 index exists and is kept in sync by triggers. When
  /// false (FTS5 or the trigram tokenizer is missing from the bundled SQLite),
  /// search must fall back to `LIKE` on `search_text`.
  bool get isFtsAvailable => _ftsAvailable;

  /// Why FTS is unavailable (diagnostics only), or null.
  String? get ftsUnavailableReason => _ftsUnavailableReason;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        beforeOpen: (OpeningDetails details) async {
          // Required for ON DELETE CASCADE.
          await customStatement('PRAGMA foreign_keys = ON');
          await _ensureFts();
        },
      );

  /// Creates the FTS5 table and sync triggers if missing (idempotent), then
  /// backfills from existing rows. Never throws: failure just disables FTS.
  Future<void> _ensureFts() async {
    try {
      if (!await _ftsObjectsExist()) {
        await customStatement(_createFtsTable);
        for (final String statement in _createFtsTriggers) {
          await customStatement(statement);
        }
        await customStatement(_rebuildFts);
      }
      _ftsAvailable = true;
      _ftsUnavailableReason = null;
    } on Exception catch (error) {
      _ftsAvailable = false;
      _ftsUnavailableReason = error.toString();
    }
  }

  Future<bool> _ftsObjectsExist() async {
    final QueryRow row = await customSelect('''
SELECT COUNT(*) AS c FROM sqlite_master
WHERE name IN ('chat_messages_fts', 'chat_messages_ai',
               'chat_messages_ad', 'chat_messages_au')
''').getSingle();
    return row.read<int>('c') == 4;
  }

  static const String _createFtsTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS chat_messages_fts USING fts5(
  search_text,
  content='chat_messages',
  content_rowid='seq',
  tokenize='trigram'
)''';

  static const List<String> _createFtsTriggers = <String>[
    '''
CREATE TRIGGER IF NOT EXISTS chat_messages_ai AFTER INSERT ON chat_messages BEGIN
  INSERT INTO chat_messages_fts(rowid, search_text)
  VALUES (new.seq, new.search_text);
END''',
    '''
CREATE TRIGGER IF NOT EXISTS chat_messages_ad AFTER DELETE ON chat_messages BEGIN
  INSERT INTO chat_messages_fts(chat_messages_fts, rowid, search_text)
  VALUES ('delete', old.seq, old.search_text);
END''',
    '''
CREATE TRIGGER IF NOT EXISTS chat_messages_au AFTER UPDATE OF search_text ON chat_messages BEGIN
  INSERT INTO chat_messages_fts(chat_messages_fts, rowid, search_text)
  VALUES ('delete', old.seq, old.search_text);
  INSERT INTO chat_messages_fts(rowid, search_text)
  VALUES (new.seq, new.search_text);
END''',
  ];

  static const String _rebuildFts =
      "INSERT INTO chat_messages_fts(chat_messages_fts) VALUES ('rebuild')";
}
