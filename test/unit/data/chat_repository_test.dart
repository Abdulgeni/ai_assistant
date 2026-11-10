import 'package:ai_assistant/data/local/app_database.dart';
import 'package:ai_assistant/data/models/chat_mappers.dart';
import 'package:ai_assistant/data/repositories/chat_repository_impl.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:ai_assistant/domain/entities/conversation.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Whole seconds, local time: what Drift round-trips exactly.
final DateTime _t0 = DateTime(2026, 3, 1, 12);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

Conversation _conv(String id, {int created = 0, int updated = 0, String title = ''}) =>
    Conversation(
      id: id,
      title: title,
      createdAt: _at(created),
      updatedAt: _at(updated),
    );

ChatMessage _msg(
  String id,
  String conversationId,
  String content, {
  int at = 0,
  ChatRole role = ChatRole.user,
  MessageStatus status = MessageStatus.complete,
  List<SourceReference> sources = const <SourceReference>[],
}) =>
    ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content,
      createdAt: _at(at),
      status: status,
      sources: sources,
    );

List<String> _ids(List<ChatMessage> messages) =>
    messages.map((ChatMessage m) => m.id).toList();

class _Env {
  _Env(this.db, this.repo);

  final AppDatabase db;
  final ChatRepositoryImpl repo;
}

Future<_Env> _open({bool forceLike = false}) async {
  final AppDatabase db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  // Opens the database now, so beforeOpen (foreign keys, FTS) has run.
  await db.customSelect('SELECT 1').get();
  return _Env(db, ChatRepositoryImpl(db, forceLikeSearch: forceLike));
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('conversations', () {
    test('saves, updates by id, and lists most recently updated first', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1', updated: 10));
      await env.repo.saveConversation(_conv('c2', updated: 20));
      await env.repo.saveConversation(_conv('c3', updated: 5));

      List<Conversation> list = await env.repo.watchConversations().first;
      expect(list.map((Conversation c) => c.id), <String>['c2', 'c1', 'c3']);

      await env.repo.saveConversation(
        _conv('c3', updated: 30, title: 'Renamed'),
      );
      list = await env.repo.watchConversations().first;
      expect(list.map((Conversation c) => c.id), <String>['c3', 'c2', 'c1']);
      expect(list.first.title, 'Renamed');
      expect(list, hasLength(3));
    });

    test('watchConversations re-emits when the data changes', () async {
      final _Env env = await _open();
      final List<List<Conversation>> emissions = <List<Conversation>>[];
      final sub = env.repo.watchConversations().listen(emissions.add);
      await _settle();
      await env.repo.saveConversation(_conv('c1'));
      await _settle();
      expect(emissions.first, isEmpty);
      expect(emissions.last.map((Conversation c) => c.id), <String>['c1']);
      await sub.cancel();
    });

    test('renameConversation changes only the title', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1', updated: 50));
      await env.repo.renameConversation('c1', 'New title');
      final Conversation c = (await env.repo.watchConversations().first).single;
      expect(c.title, 'New title');
      expect(c.updatedAt, _at(50));
    });

    test('deleting a conversation removes its messages only', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveConversation(_conv('c2'));
      await env.repo.saveMessage(_msg('a', 'c1', 'one'));
      await env.repo.saveMessage(_msg('b', 'c2', 'two'));

      await env.repo.deleteConversation('c1');

      expect(await env.repo.loadMessages('c1'), isEmpty);
      expect(_ids(await env.repo.loadMessages('c2')), <String>['b']);
    });
  });

  group('messages', () {
    test('round-trips content and sources, oldest first', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      final ChatMessage first = _msg('m1', 'c1', 'مرحبا 👋', at: 1);
      final ChatMessage second = _msg(
        'm2',
        'c1',
        'أهلًا بك',
        at: 2,
        role: ChatRole.assistant,
        sources: const <SourceReference>[
          SourceReference(id: 's1', title: 'مستند', uri: 'https://x', snippet: 'س'),
          SourceReference(id: 's2', title: 'Doc'),
        ],
      );
      await env.repo.saveMessage(second);
      await env.repo.saveMessage(first);

      // Insertion order, not timestamp order, defines the timeline.
      expect(await env.repo.loadMessages('c1'), <ChatMessage>[second, first]);
    });

    test('a streaming placeholder is upserted in place when completed', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(_msg('u', 'c1', 'question', at: 1));
      await env.repo.saveMessage(
        _msg('a', 'c1', '', at: 2, role: ChatRole.assistant, status: MessageStatus.streaming),
      );
      await env.repo.saveMessage(_msg('z', 'c1', 'later', at: 3));

      ChatMessageRow row = await (env.db.select(env.db.chatMessages)
            ..where((m) => m.id.equals('a')))
          .getSingle();
      expect(row.isCommitted, isFalse);
      expect(row.status, 'streaming');

      await env.repo.saveMessage(
        _msg('a', 'c1', 'the answer', at: 2, role: ChatRole.assistant),
      );

      final List<ChatMessage> messages = await env.repo.loadMessages('c1');
      expect(_ids(messages), <String>['u', 'a', 'z']);
      expect(messages[1].content, 'the answer');
      expect(messages[1].status, MessageStatus.complete);
      row = await (env.db.select(env.db.chatMessages)
            ..where((m) => m.id.equals('a')))
          .getSingle();
      expect(row.isCommitted, isTrue);
    });

    test('upserting can clear sources', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(
        _msg('a', 'c1', 'x', sources: const <SourceReference>[SourceReference(id: 's', title: 'T')]),
      );
      await env.repo.saveMessage(_msg('a', 'c1', 'x'));
      expect((await env.repo.loadMessages('c1')).single.sources, isEmpty);
    });

    test('saving into a missing conversation throws and stores nothing', () async {
      final _Env env = await _open();
      await expectLater(
        env.repo.saveMessage(_msg('a', 'ghost', 'x')),
        throwsStateError,
      );
      expect(await env.db.select(env.db.chatMessages).get(), isEmpty);
    });

    test('saving bumps the conversation forward, never backward', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1', updated: 100));

      await env.repo.saveMessage(_msg('old', 'c1', 'x', at: 50));
      expect((await env.repo.watchConversations().first).single.updatedAt, _at(100));

      await env.repo.saveMessage(_msg('new', 'c1', 'y', at: 200));
      expect((await env.repo.watchConversations().first).single.updatedAt, _at(200));
    });

    test('deleteMessage removes one message', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(_msg('a', 'c1', 'x'));
      await env.repo.saveMessage(_msg('b', 'c1', 'y'));
      await env.repo.deleteMessage('a');
      expect(_ids(await env.repo.loadMessages('c1')), <String>['b']);
    });

    test('unreadable rows are skipped; an unknown status becomes failed', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(_msg('ok', 'c1', 'fine'));
      await env.db.into(env.db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              id: 'alien',
              conversationId: 'c1',
              role: 'alien',
              content: 'x',
              searchText: 'x',
              createdAt: _at(0),
              status: 'complete',
            ),
          );
      await env.db.into(env.db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              id: 'odd',
              conversationId: 'c1',
              role: 'user',
              content: 'y',
              searchText: 'y',
              createdAt: _at(0),
              status: 'from-the-future',
            ),
          );

      final List<ChatMessage> messages = await env.repo.loadMessages('c1');
      expect(_ids(messages), <String>['ok', 'odd']);
      expect(messages.last.status, MessageStatus.failed);
    });
  });

  group('paging', () {
    Future<_Env> seeded() async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveConversation(_conv('c2'));
      for (var i = 0; i < 120; i++) {
        await env.repo.saveMessage(
          _msg('m${i.toString().padLeft(3, '0')}', 'c1', 'message $i', at: i),
        );
      }
      await env.repo.saveMessage(_msg('other', 'c2', 'elsewhere'));
      return env;
    }

    test('the default page is the newest 50, oldest first', () async {
      final _Env env = await seeded();
      final List<String> ids = _ids(await env.repo.loadMessages('c1'));
      expect(ids, hasLength(50));
      expect(ids.first, 'm070');
      expect(ids.last, 'm119');
    });

    test('beforeMessageId pages upward', () async {
      final _Env env = await seeded();
      final List<String> ids =
          _ids(await env.repo.loadMessages('c1', beforeMessageId: 'm070'));
      expect(ids.first, 'm020');
      expect(ids.last, 'm069');
      expect(
        _ids(await env.repo.loadMessages('c1', limit: 3, beforeMessageId: 'm005')),
        <String>['m002', 'm003', 'm004'],
      );
    });

    test('paging through everything yields each message exactly once', () async {
      final _Env env = await seeded();
      final List<String> all = <String>[];
      String? cursor;
      for (;;) {
        final List<ChatMessage> page = await env.repo.loadMessages(
          'c1',
          limit: 25,
          beforeMessageId: cursor,
        );
        if (page.isEmpty) break;
        all.insertAll(0, _ids(page));
        cursor = page.first.id;
      }
      expect(all, hasLength(120));
      expect(all.toSet(), hasLength(120));
      expect(all.first, 'm000');
      expect(all.last, 'm119');
    });

    test('the first message, an unknown cursor, or a foreign cursor give an empty page',
        () async {
      final _Env env = await seeded();
      expect(await env.repo.loadMessages('c1', beforeMessageId: 'm000'), isEmpty);
      expect(await env.repo.loadMessages('c1', beforeMessageId: 'nope'), isEmpty);
      expect(await env.repo.loadMessages('c1', beforeMessageId: 'other'), isEmpty);
    });
  });

  group('recoverInterruptedStreams', () {
    test('marks streaming and uncommitted rows failed, keeps content', () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(_msg('done', 'c1', 'complete answer'));
      await env.repo.saveMessage(
        _msg('cut', 'c1', 'partial', role: ChatRole.assistant, status: MessageStatus.streaming),
      );
      // Inconsistent rows: flag and status disagree.
      await env.db.into(env.db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              id: 'odd1',
              conversationId: 'c1',
              role: 'assistant',
              content: 'a',
              searchText: 'a',
              createdAt: _at(0),
              status: 'streaming',
            ),
          );
      await env.db.into(env.db.chatMessages).insert(
            ChatMessagesCompanion.insert(
              id: 'odd2',
              conversationId: 'c1',
              role: 'assistant',
              content: 'b',
              searchText: 'b',
              createdAt: _at(0),
              status: 'complete',
              isCommitted: const Value<bool>(false),
            ),
          );

      expect(await env.repo.recoverInterruptedStreams(), 3);

      final List<ChatMessage> messages = await env.repo.loadMessages('c1');
      expect(
        messages.map((ChatMessage m) => m.status),
        <MessageStatus>[
          MessageStatus.complete,
          MessageStatus.failed,
          MessageStatus.failed,
          MessageStatus.failed,
        ],
      );
      expect(messages[1].content, 'partial');
      expect(messages.every((ChatMessage m) => m.isCommitted), isTrue);
    });

    test('is idempotent and touches nothing when there is nothing to fix',
        () async {
      final _Env env = await _open();
      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(_msg('a', 'c1', 'fine'));
      expect(await env.repo.recoverInterruptedStreams(), 0);
      expect(await env.repo.recoverInterruptedStreams(), 0);
    });
  });

  for (final bool forceLike in <bool>[false, true]) {
    group('search (${forceLike ? 'LIKE fallback' : 'FTS when available'})', () {
      Future<_Env> seeded() async {
        final _Env env = await _open(forceLike: forceLike);
        await env.repo.saveConversation(_conv('c1'));
        await env.repo.saveConversation(_conv('c2'));
        await env.repo.saveMessage(
          _msg('m1', 'c1', 'مرحباً، أريد معلومات عن المَدْرَسَة الجديدة', at: 1),
        );
        await env.repo.saveMessage(
          _msg('m2', 'c1', 'Tell me about the Café menu for 2025', at: 2),
        );
        await env.repo.saveMessage(
          _msg('m3', 'c1', 'رقم الهاتف ٠١٢٣٤٥ وأحمد وإبراهيم', at: 3),
        );
        await env.repo.saveMessage(
          _msg('m4', 'c2', 'meeting notes: 50%_discount', at: 4),
        );
        return env;
      }

      Future<List<String>> find(_Env env, String query) async =>
          _ids(await env.repo.searchMessages(query));

      test('ignores diacritics, hamza, and ta marbuta', () async {
        final _Env env = await seeded();
        expect(await find(env, 'مدرسة'), <String>['m1']);
        expect(await find(env, 'مدرسه'), <String>['m1']);
      });

      test('finds words with an attached article or conjunction', () async {
        final _Env env = await seeded();
        expect(await find(env, 'احمد'), <String>['m3']);
        expect(await find(env, 'ابراهيم'), <String>['m3']);
      });

      test('treats Arabic-Indic and Latin digits alike', () async {
        final _Env env = await seeded();
        expect(await find(env, '012345'), <String>['m3']);
        expect(await find(env, '٢٠٢٥'), <String>['m2']);
      });

      test('is case-insensitive and matches substrings', () async {
        final _Env env = await seeded();
        expect(await find(env, 'CAF'), <String>['m2']);
      });

      test('requires every term to match', () async {
        // FTS matches terms anywhere; LIKE needs the whole phrase contiguously.
        if (forceLike) return;
        final _Env env = await seeded();
        expect(await find(env, 'معلومات الجديده'), <String>['m1']);
        expect(await find(env, 'معلومات cafe'), isEmpty);
      });

      test('short terms (under 3 characters) still work', () async {
        final _Env env = await seeded();
        expect(await find(env, 'عن'), <String>['m1']);
      });

      test('treats % and _ literally', () async {
        final _Env env = await seeded();
        expect(await find(env, '50%_'), <String>['m4']);
        expect(await find(env, '%'), <String>['m4']);
      });

      test('blank or whitespace queries return nothing', () async {
        final _Env env = await seeded();
        expect(await find(env, ''), isEmpty);
        expect(await find(env, '   '), isEmpty);
      });

      test('no match returns nothing', () async {
        final _Env env = await seeded();
        expect(await find(env, 'zzzzzz'), isEmpty);
      });

      test('limit caps the results', () async {
        final _Env env = await seeded();
        for (var i = 0; i < 5; i++) {
          await env.repo.saveMessage(_msg('x$i', 'c1', 'كلمة مشتركة $i', at: 10 + i));
        }
        expect(
          (await env.repo.searchMessages('مشتركه', limit: 2)).length,
          2,
        );
      });

      test('stays in sync with edits and deletes', () async {
        final _Env env = await seeded();
        await env.repo.saveMessage(_msg('m1', 'c1', 'نص جديد تماما', at: 1));
        expect(await find(env, 'مدرسة'), isEmpty);
        expect(await find(env, 'تماما'), <String>['m1']);

        await env.repo.deleteMessage('m2');
        expect(await find(env, 'CAF'), isEmpty);

        await env.repo.deleteConversation('c2');
        expect(await find(env, '50%_'), isEmpty);
      });
    });
  }

  group('FTS index', () {
    test('reports availability and, when present, tracks the table', () async {
      final _Env env = await _open();
      // ignore: avoid_print
      print(
        'FTS available: ${env.db.isFtsAvailable} '
        '(${env.db.ftsUnavailableReason ?? 'ok'})',
      );
      if (!env.db.isFtsAvailable) {
        // Vacuous pass: this host's SQLite lacks FTS5 or the trigram tokenizer.
        // The LIKE-fallback tests above still cover search behaviour.
        return;
      }
      Future<int> hits() async => (await env.db
              .customSelect(
                // ignore: prefer_single_quotes
                "SELECT COUNT(*) AS c FROM chat_messages_fts "
                    "WHERE chat_messages_fts MATCH '\"مدرسه\"'",
              )
              .getSingle())
          .read<int>('c');

      await env.repo.saveConversation(_conv('c1'));
      await env.repo.saveMessage(_msg('m1', 'c1', 'المَدْرَسَة'));
      expect(await hits(), 1);
      await env.repo.deleteMessage('m1');
      expect(await hits(), 0);
    });
  });

  group('mappers', () {
    ChatMessageRow row({String role = 'user', String status = 'complete', String? sources}) =>
        ChatMessageRow(
          seq: 1,
          id: 'm',
          conversationId: 'c',
          role: role,
          content: 'x',
          searchText: 'x',
          createdAt: _at(0),
          status: status,
          isCommitted: true,
          sourcesJson: sources,
        );

    test('isCommitted is derived from the status', () {
      for (final MessageStatus status in MessageStatus.values) {
        final ChatMessagesCompanion companion =
            chatMessageToCompanion(_msg('m', 'c', 'x', status: status));
        expect(
          companion.isCommitted.value,
          status != MessageStatus.streaming,
          reason: status.name,
        );
      }
    });

    test('search text is normalized, content is untouched', () {
      final ChatMessagesCompanion companion =
          chatMessageToCompanion(_msg('m', 'c', 'المَدْرَسَة'));
      expect(companion.content.value, 'المَدْرَسَة');
      expect(companion.searchText.value, 'المدرسه');
    });

    test('an unknown role is unreadable; an unknown status is failed', () {
      expect(tryChatMessageFromRow(row(role: 'alien')), isNull);
      expect(
        tryChatMessageFromRow(row(status: 'from-the-future'))!.status,
        MessageStatus.failed,
      );
    });

    test('sources round-trip and tolerate garbage', () {
      const List<SourceReference> sources = <SourceReference>[
        SourceReference(id: 'a', title: 'A', uri: 'https://x', snippet: 's'),
        SourceReference(id: 'b', title: 'B'),
      ];
      expect(decodeSources(encodeSources(sources)), sources);
      expect(encodeSources(const <SourceReference>[]), isNull);
      expect(decodeSources(null), isEmpty);
      expect(decodeSources('not json'), isEmpty);
      expect(decodeSources('{"a":1}'), isEmpty);
      expect(
        decodeSources('[{"id":"a"},"x",{"id":"b","title":"T"}]'),
        const <SourceReference>[SourceReference(id: 'b', title: 'T')],
      );
    });
  });
}
