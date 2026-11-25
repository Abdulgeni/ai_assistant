/// Turns Markdown into something that sounds right when read aloud: no
/// asterisks, no `#`, no URLs, link text kept, code spans read as their text,
/// list markers and table pipes dropped. Fenced code blocks are removed
/// entirely (the chunker skips them before they get here).
String markdownToSpeech(String text) {
  var t = text;
  t = t.replaceAll(RegExp(r'```[\s\S]*?```'), '');
  t = t.replaceAll(RegExp(r'^\s*([-*_]\s*){3,}$', multiLine: true), '');
  if (t.contains('|')) {
    t = t.replaceAll(RegExp(r'^[\s|:\-]+$', multiLine: true), '');
  }
  t = t.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), (Match m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (Match m) => m[1]!);
  t = t.replaceAll(RegExp(r'https?://\S+'), '');
  t = t.replaceAllMapped(RegExp(r'`([^`]*)`'), (Match m) => m[1]!);
  t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*\d+[.)]\s*$', multiLine: true), '');
  t = t.replaceAll(RegExp(r'(\*\*|__|~~)'), '');
  t = t.replaceAll('*', '');
  // Emphasis underscores, but not snake_case (Unicode-aware, so Arabic letters
  // count as word characters).
  t = t.replaceAll(
    RegExp(r'(?<![\p{L}\p{N}_])_|_(?![\p{L}\p{N}_])', unicode: true),
    '',
  );
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAll('|', ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const Set<int> _terminators = <int>{
  0x2E, // .
  0x21, // !
  0x3F, // ?
  0x2026, // …
  0x061F, // ؟
  0x3002, // 。
  0x0A, // newline: a line is always a unit of speech
};

bool _isBlank(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0D || unit == 0x0A;

/// Cuts a GROWING Markdown reply into sentences to speak as they complete.
///
/// Feed it the full text so far each time (it only ever grows). It returns the
/// newly completed sentences, already cleaned for speech, and remembers how
/// far it got. The output is the same for any schedule of growth, so a sentence
/// is never spoken twice or skipped however the tokens arrive.
///
///  * A sentence ends at `. ! ? … ؟ 。` followed by whitespace, or at a
///    newline. A trailing `.` waits for more text (it could be a decimal).
///  * A `.` right after a list number (`1.`) is not a sentence end.
///  * Fenced code blocks are skipped entirely; an unclosed fence waits.
///  * With [isFinal] the remainder is flushed.
///  * [maxPending] flushes a very long run with no punctuation at the last
///    space, so speech does not stall (this one depends on feed granularity).
final class SpeechChunker {
  SpeechChunker({this.maxPending = 1 << 30});

  final int maxPending;
  int _consumed = 0;

  void reset() => _consumed = 0;

  List<String> add(String text, {bool isFinal = false}) {
    final List<String> out = <String>[];
    while (true) {
      var q = _consumed;
      while (q < text.length && _isBlank(text.codeUnitAt(q))) {
        q++;
      }
      if (text.startsWith('```', q)) {
        final int end = text.indexOf('```', q + 3);
        if (end == -1) {
          if (isFinal) _consumed = text.length;
          break;
        }
        final int newline = text.indexOf('\n', end + 3);
        _consumed = newline == -1 ? text.length : newline + 1;
        continue;
      }
      final int? boundary = _boundary(text, isFinal);
      if (boundary == null) break;
      final String segment = text.substring(_consumed, boundary);
      _consumed = boundary;
      final String cleaned = markdownToSpeech(segment);
      if (cleaned.isNotEmpty) out.add(cleaned);
    }
    return out;
  }

  int? _boundary(String text, bool isFinal) {
    final int n = text.length;
    for (var i = _consumed; i < n; i++) {
      final int ch = text.codeUnitAt(i);
      if (!_terminators.contains(ch)) continue;
      if (ch == 0x0A) return i + 1;
      if (ch == 0x2E && _isListNumber(text, i)) continue;
      if (i + 1 == n) {
        if (isFinal) return n;
        continue;
      }
      if (_isBlank(text.codeUnitAt(i + 1))) return i + 1;
    }
    if (_consumed >= n) return null;
    if (isFinal) return n;
    if (n - _consumed > maxPending) {
      for (var i = n - 1; i > _consumed; i--) {
        final int unit = text.codeUnitAt(i);
        if (unit == 0x20 || unit == 0x09) return i + 1;
      }
    }
    return null;
  }

  static bool _isListNumber(String text, int i) {
    final int start = i == 0 ? 0 : text.lastIndexOf('\n', i - 1) + 1;
    final String prefix = text.substring(start, i).trim();
    return prefix.isNotEmpty && RegExp(r'^\d+$').hasMatch(prefix);
  }
}
