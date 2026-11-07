import 'dart:convert';
import 'dart:math';

import 'package:ai_assistant/core/network/sse_exceptions.dart';
import 'package:ai_assistant/core/network/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<SseMessage> _parse(
  List<String> chunks, {
  SseLimits limits = const SseLimits(),
}) {
  final SseParser parser = SseParser(limits: limits);
  final List<SseMessage> out = <SseMessage>[];
  for (final String chunk in chunks) {
    out.addAll(parser.add(chunk));
  }
  parser.close();
  return out;
}

SseMessage _m(
  String data, {
  String event = 'message',
  String? id,
  Duration? retry,
}) =>
    SseMessage(event: event, data: data, id: id, retry: retry);

Future<List<SseMessage>> _decode(List<List<int>> chunks) =>
    decodeSseBytes(Stream<List<int>>.fromIterable(chunks)).toList();

void main() {
  group('spec examples', () {
    test('multiple data lines are joined with a newline', () {
      expect(
        _parse(<String>['data: YHOO\ndata: +2\ndata: 10\n\n']),
        <SseMessage>[_m('YHOO\n+2\n10')],
      );
    });

    test('comments, ids, empty id, and one leading space stripped', () {
      expect(
        _parse(<String>[
          ': test stream\n\ndata: first event\nid: 1\n\n'
              'data:second event\nid\n\ndata:  third event\n\n',
        ]),
        <SseMessage>[
          _m('first event', id: '1'),
          _m('second event', id: ''),
          _m(' third event', id: ''),
        ],
      );
    });

    test('empty data, two empty data lines, unterminated tail dropped', () {
      expect(
        _parse(<String>['data\n\ndata\ndata\n\ndata:']),
        <SseMessage>[_m(''), _m('\n')],
      );
    });

    test('"data:test" equals "data: test"', () {
      expect(
        _parse(<String>['data:test\n\ndata: test\n\n']),
        <SseMessage>[_m('test'), _m('test')],
      );
    });
  });

  group('fields', () {
    test('event type applies to one event, then resets', () {
      expect(
        _parse(<String>['event: token\ndata: a\n\ndata: b\n\n']),
        <SseMessage>[_m('a', event: 'token'), _m('b')],
      );
    });

    test('a block without data dispatches nothing and resets the type', () {
      expect(
        _parse(<String>['event: x\n\ndata: y\n\n']),
        <SseMessage>[_m('y')],
      );
    });

    test('retry is parsed; an invalid retry is ignored', () {
      expect(
        _parse(<String>['retry: 1500\ndata: a\n\nretry: abc\ndata: b\n\n']),
        <SseMessage>[
          _m('a', retry: const Duration(milliseconds: 1500)),
          _m('b'),
        ],
      );
    });

    test('unknown fields are ignored', () {
      expect(_parse(<String>['foo: bar\ndata: a\n\n']), <SseMessage>[_m('a')]);
    });

    test('an id containing NUL is ignored', () {
      expect(
        _parse(<String>['id: a\u0000b\ndata: x\n\n']),
        <SseMessage>[_m('x')],
      );
    });

    test('colons inside the value are kept', () {
      expect(
        _parse(<String>['data: {"a":"b:c"}\n\n']),
        <SseMessage>[_m('{"a":"b:c"}')],
      );
    });

    test('[DONE] is ordinary data at this layer', () {
      expect(
        _parse(<String>['data: [DONE]\n\n']),
        <SseMessage>[_m('[DONE]')],
      );
    });

    test('heartbeat comments produce no messages', () {
      expect(_parse(<String>[': hb\n\n: hb\n\n']), isEmpty);
    });

    test('Arabic and emoji payloads survive', () {
      expect(
        _parse(<String>['data: {"text":"مرحبا 👋"}\n\n']),
        <SseMessage>[_m('{"text":"مرحبا 👋"}')],
      );
    });
  });

  group('line endings', () {
    test('CRLF', () {
      expect(
        _parse(<String>['data: a\r\n\r\ndata: b\r\n\r\n']),
        <SseMessage>[_m('a'), _m('b')],
      );
    });

    test('bare CR', () {
      expect(
        _parse(<String>['data: a\r\rdata: b\r\r']),
        <SseMessage>[_m('a'), _m('b')],
      );
    });

    test('mixed endings', () {
      expect(
        _parse(<String>['data: a\n\r\ndata: b\r\n\n']),
        <SseMessage>[_m('a'), _m('b')],
      );
    });

    test('CR at the end of one chunk and LF at the start of the next', () {
      expect(
        _parse(<String>['data: a\r', '\ndata: b\r\n\r', '\n']),
        <SseMessage>[_m('a\nb')],
      );
    });
  });

  group('BOM and truncation', () {
    test('a BOM at the very start is stripped', () {
      expect(
        _parse(<String>['\ufeffdata: a\n\n']),
        <SseMessage>[_m('a')],
      );
    });

    test('a BOM later in the stream is not special', () {
      expect(
        _parse(<String>['data: a\n\n', '\ufeffdata: b\n\n']),
        <SseMessage>[_m('a')],
      );
    });

    test('an unterminated trailing event is discarded', () {
      expect(
        _parse(<String>['data: a\n\ndata: b']),
        <SseMessage>[_m('a')],
      );
    });

    test('hasIncompleteEvent reports buffered input', () {
      final SseParser parser = SseParser()..add('data: a');
      expect(parser.hasIncompleteEvent, isTrue);
      parser.add('\n\n');
      expect(parser.hasIncompleteEvent, isFalse);
    });

    test('add after close throws', () {
      final SseParser parser = SseParser()..close();
      expect(() => parser.add('x'), throwsStateError);
    });
  });

  group('limits', () {
    test('a line over the limit throws, across chunks', () {
      expect(
        () => _parse(
          <String>['data: ', 'x' * 50],
          limits: const SseLimits(maxLineLength: 10),
        ),
        throwsA(isA<SseFormatException>()),
      );
    });

    test('a line that never ends still hits the limit', () {
      final SseParser parser =
          SseParser(limits: const SseLimits(maxLineLength: 10));
      expect(
        () {
          for (var i = 0; i < 20; i++) {
            parser.add('ab');
          }
        },
        throwsA(isA<SseFormatException>()),
      );
    });

    test('an event over the data limit throws', () {
      expect(
        () => _parse(
          <String>['data: aaaa\ndata: bbbb\ndata: cccc\n\n'],
          limits: const SseLimits(maxEventDataLength: 10),
        ),
        throwsA(isA<SseFormatException>()),
      );
    });
  });

  group('chunking never changes the result', () {
    const String sample =
        'event: token\r\ndata: {"text":"مرحبًا 👋"}\r\n\r\n'
        ': hb\n\nid: 7\ndata: a\ndata: b\n\n'
        'event: done\rdata: {}\r\r';

    test('split at every position', () {
      final List<SseMessage> whole = _parse(<String>[sample]);
      expect(whole, hasLength(3));
      for (var i = 0; i <= sample.length; i++) {
        expect(
          _parse(<String>[sample.substring(0, i), sample.substring(i)]),
          whole,
          reason: 'split at $i',
        );
      }
    });

    test('one character at a time', () {
      expect(
        _parse(sample.split('')),
        _parse(<String>[sample]),
      );
    });

    test('random streams under random chunkings', () {
      final Random random = Random(7);
      for (var trial = 0; trial < 300; trial++) {
        final String stream = _generate(random);
        final List<SseMessage> reference = _parse(<String>[stream]);
        for (var k = 0; k < 15; k++) {
          final List<int> cuts = <int>{
            for (var j = 0; j < 1 + random.nextInt(6); j++)
              random.nextInt(stream.length + 1),
          }.toList()
            ..sort();
          final List<String> chunks = <String>[];
          var previous = 0;
          for (final int cut in cuts) {
            chunks.add(stream.substring(previous, cut));
            previous = cut;
          }
          chunks.add(stream.substring(previous));
          expect(_parse(chunks), reference, reason: 'chunks: $chunks');
        }
      }
    });
  });

  group('decodeSseBytes (UTF-8)', () {
    final List<int> bytes = utf8.encode(
      'event: token\ndata: {"text":"مرحبًا بالعالم 👋🏽 ثم"}\n\n'
      'event: done\ndata: {}\n\n',
    );

    test('decodes the whole stream', () async {
      final List<SseMessage> messages = await _decode(<List<int>>[bytes]);
      expect(messages, hasLength(2));
      expect(messages.first.data, '{"text":"مرحبًا بالعالم 👋🏽 ثم"}');
    });

    test('split at every byte boundary, including mid-character', () async {
      final List<SseMessage> whole = await _decode(<List<int>>[bytes]);
      for (var i = 0; i <= bytes.length; i++) {
        expect(
          await _decode(<List<int>>[bytes.sublist(0, i), bytes.sublist(i)]),
          whole,
          reason: 'byte split at $i',
        );
      }
    });

    test('one byte at a time', () async {
      final List<SseMessage> whole = await _decode(<List<int>>[bytes]);
      expect(
        await _decode(<List<int>>[
          for (final int b in bytes) <int>[b],
        ]),
        whole,
      );
    });

    test('invalid UTF-8 throws SseFormatException', () {
      expect(
        _decode(<List<int>>[
          <int>[...'data: '.codeUnits, 0xFF, 0xFE, 0x0A, 0x0A],
        ]),
        throwsA(isA<SseFormatException>()),
      );
    });

    test('a stream ending mid-character throws SseFormatException', () {
      final List<int> truncated = utf8.encode('data: م\n\n');
      expect(
        _decode(<List<int>>[truncated.sublist(0, 7)]),
        throwsA(isA<SseFormatException>()),
      );
    });
  });
}

String _generate(Random random) {
  final String newline = <String>['\n', '\r\n', '\r'][random.nextInt(3)];
  const List<String> payloads = <String>[
    '{"text":"مرحبا"}',
    '{"text":"a:b"}',
    'plain',
    '[DONE]',
    '',
    '😀 ok',
  ];
  final StringBuffer out = StringBuffer();
  for (var e = 0; e < 1 + random.nextInt(6); e++) {
    if (random.nextDouble() < 0.15) {
      out.write(': keepalive$newline$newline');
      continue;
    }
    if (random.nextBool()) {
      out.write(
        'event: ${<String>['token', 'sources', 'done', 'error'][random.nextInt(4)]}'
        '$newline',
      );
    }
    if (random.nextDouble() < 0.3) {
      out.write('id: ${1 + random.nextInt(99)}$newline');
    }
    for (var d = 0; d < 1 + random.nextInt(3); d++) {
      final String prefix = <String>['data: ', 'data:', 'data :'][random.nextInt(3)];
      out.write('$prefix${payloads[random.nextInt(payloads.length)]}$newline');
    }
    out.write(newline);
  }
  return out.toString();
}
