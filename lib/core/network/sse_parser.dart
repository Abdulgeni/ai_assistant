import 'dart:convert';

import 'package:ai_assistant/core/network/sse_exceptions.dart';

/// One dispatched Server-Sent Event.
final class SseMessage {
  const SseMessage({
    required this.event,
    required this.data,
    this.id,
    this.retry,
  });

  /// Event type used when the stream does not name one.
  static const String defaultEvent = 'message';

  /// The `event:` value, or [defaultEvent].
  final String event;

  /// All `data:` lines joined with `\n`.
  final String data;

  /// The last `id:` value seen on the stream (persists across events), if any.
  final String? id;

  /// A `retry:` value given in this event's block, if any.
  final Duration? retry;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SseMessage &&
          event == other.event &&
          data == other.data &&
          id == other.id &&
          retry == other.retry);

  @override
  int get hashCode => Object.hash(event, data, id, retry);

  // Never print payloads: they are assistant text.
  @override
  String toString() => 'SseMessage(event: $event, chars: ${data.length})';
}

/// Defensive size limits, so a buggy or hostile server cannot exhaust memory.
final class SseLimits {
  const SseLimits({
    this.maxLineLength = 256 * 1024,
    this.maxEventDataLength = 1024 * 1024,
  });

  /// Maximum characters in a single line.
  final int maxLineLength;

  /// Maximum characters of `data` accumulated for one event.
  final int maxEventDataLength;
}

const int _cr = 0x0D;
const int _lf = 0x0A;
const int _colon = 0x3A;
const int _bom = 0xFEFF;

/// Incremental parser for the `text/event-stream` format (WHATWG HTML spec,
/// "Server-sent events").
///
/// Feed it decoded text chunks of ANY size and split at ANY position (mid-line,
/// between a CR and its LF, between UTF-16 surrogates); results are identical
/// to feeding the whole text at once.
///
/// After an [SseFormatException] the parser is unusable; discard it.
final class SseParser {
  SseParser({this.limits = const SseLimits()});

  final SseLimits limits;

  static final RegExp _digits = RegExp(r'^[0-9]+$');

  final StringBuffer _line = StringBuffer();
  int _lineLength = 0;
  bool _skipLf = false;
  bool _atStart = true;
  bool _closed = false;

  final List<String> _dataLines = <String>[];
  int _dataLength = 0;
  String? _eventType;
  String? _lastEventId;
  Duration? _retry;

  /// True while a partial line or an undispatched event is buffered.
  bool get hasIncompleteEvent => _line.isNotEmpty || _dataLines.isNotEmpty;

  /// Consumes [chunk] and returns every event it completed.
  List<SseMessage> add(String chunk) {
    if (_closed) throw StateError('SseParser is closed.');
    final List<SseMessage> out = <SseMessage>[];

    var text = chunk;
    if (_atStart && text.isNotEmpty) {
      _atStart = false;
      if (text.codeUnitAt(0) == _bom) text = text.substring(1);
    }

    var segmentStart = 0;
    for (var i = 0; i < text.length; i++) {
      final int unit = text.codeUnitAt(i);
      if (_skipLf) {
        _skipLf = false;
        if (unit == _lf) {
          // The LF of a CRLF whose CR ended the previous line.
          segmentStart = i + 1;
          continue;
        }
      }
      if (unit == _cr || unit == _lf) {
        _appendToLine(text, segmentStart, i);
        _endLine(out);
        segmentStart = i + 1;
        _skipLf = unit == _cr;
      }
    }
    _appendToLine(text, segmentStart, text.length);
    return out;
  }

  /// Ends the stream. Per the spec, an incomplete trailing event (no blank line
  /// after it) is discarded, not dispatched.
  void close() {
    _closed = true;
    _line.clear();
    _dataLines.clear();
  }

  void _appendToLine(String text, int start, int end) {
    if (end <= start) return;
    _line.write(text.substring(start, end));
    _lineLength += end - start;
    if (_lineLength > limits.maxLineLength) {
      throw const SseFormatException('SSE line exceeds the size limit.');
    }
  }

  void _endLine(List<SseMessage> out) {
    final String line = _line.toString();
    _line.clear();
    _lineLength = 0;
    _processLine(line, out);
  }

  void _processLine(String line, List<SseMessage> out) {
    if (line.isEmpty) {
      _dispatch(out);
      return;
    }
    if (line.codeUnitAt(0) == _colon) return; // comment / keep-alive

    final int colon = line.indexOf(':');
    final String field;
    String value;
    if (colon == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }

    switch (field) {
      case 'data':
        _dataLength += value.length + 1;
        if (_dataLength > limits.maxEventDataLength) {
          throw const SseFormatException('SSE event exceeds the size limit.');
        }
        _dataLines.add(value);
      case 'event':
        _eventType = value;
      case 'id':
        if (!value.contains('\u0000')) _lastEventId = value;
      case 'retry':
        if (_digits.hasMatch(value)) {
          final int? milliseconds = int.tryParse(value);
          if (milliseconds != null) {
            _retry = Duration(milliseconds: milliseconds);
          }
        }
      default:
        break; // unknown fields are ignored
    }
  }

  void _dispatch(List<SseMessage> out) {
    if (_dataLines.isEmpty) {
      // A block without data dispatches nothing.
      _eventType = null;
      _retry = null;
      return;
    }
    out.add(
      SseMessage(
        event: _eventType ?? SseMessage.defaultEvent,
        data: _dataLines.join('\n'),
        id: _lastEventId,
        retry: _retry,
      ),
    );
    _dataLines.clear();
    _dataLength = 0;
    _eventType = null;
    _retry = null;
  }
}

/// Decodes a byte stream into SSE messages.
///
/// Uses the chunk-aware `utf8.decoder`, so a multi-byte character (Arabic
/// letters are 2 bytes, emoji 4) split across network packets decodes
/// correctly. Invalid UTF-8, or a stream ending mid-character, throws
/// [SseFormatException]. Cancelling the returned stream cancels [bytes].
Stream<SseMessage> decodeSseBytes(
  Stream<List<int>> bytes, {
  SseLimits limits = const SseLimits(),
}) async* {
  final SseParser parser = SseParser(limits: limits);
  try {
    await for (final String text in utf8.decoder.bind(bytes)) {
      for (final SseMessage message in parser.add(text)) {
        yield message;
      }
    }
  } on FormatException catch (error) {
    throw SseFormatException('Invalid UTF-8 in event stream: ${error.message}');
  }
  parser.close();
}
