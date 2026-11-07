/// Search normalization shared by writes (the `search_text` column) and queries.
///
/// Folds Arabic spelling variants so "مدرسة" finds "المَدْرَسَة", maps Arabic-Indic
/// and Persian digits to ASCII, lowercases Latin, and collapses whitespace.
/// The result is for matching only: its length differs from the original, so it
/// must never be displayed or used for offsets into the original text.
String normalizeForSearch(String input) {
  final StringBuffer out = StringBuffer();
  var pendingSpace = false;
  for (final int rune in input.runes) {
    if (_isIgnorable(rune)) continue;
    final int folded = _fold(rune);
    if (_isSpace(folded)) {
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) {
      out.write(' ');
      pendingSpace = false;
    }
    out.writeCharCode(folded);
  }
  return out.toString().toLowerCase();
}

/// The FTS5 `trigram` tokenizer needs at least 3 characters per term.
const int _minTrigramLength = 3;

/// Builds an FTS5 MATCH expression (terms ANDed, each quoted), or null when no
/// term is long enough. A null result means: use [buildLikePattern] instead.
String? buildFtsMatchQuery(String userInput) {
  final List<String> terms = normalizeForSearch(userInput)
      .split(' ')
      .where((String t) => t.runes.length >= _minTrigramLength)
      .toList();
  if (terms.isEmpty) return null;
  return terms.map((String t) => '"${t.replaceAll('"', '""')}"').join(' ');
}

/// The escape character to use with `LIKE ? ESCAPE '\'`.
const String likeEscapeCharacter = r'\';

/// Builds a `%...%` LIKE pattern over the normalized text, or null for a blank
/// query. Use with `ESCAPE '\'`.
String? buildLikePattern(String userInput) {
  final String normalized = normalizeForSearch(userInput);
  if (normalized.isEmpty) return null;
  final String escaped = normalized
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

/// Arabic diacritics (harakat), superscript alef, tatweel, and invisible bidi
/// controls.
bool _isIgnorable(int r) =>
    (r >= 0x064B && r <= 0x065F) ||
    r == 0x0670 ||
    r == 0x0640 ||
    r == 0x061C ||
    (r >= 0x200C && r <= 0x200F) ||
    (r >= 0x202A && r <= 0x202E) ||
    (r >= 0x2066 && r <= 0x2069);

bool _isSpace(int r) =>
    r == 0x20 ||
    (r >= 0x09 && r <= 0x0D) ||
    r == 0xA0 ||
    r == 0x1680 ||
    (r >= 0x2000 && r <= 0x200A) ||
    r == 0x2028 ||
    r == 0x2029 ||
    r == 0x202F ||
    r == 0x205F ||
    r == 0x3000;

int _fold(int r) => switch (r) {
      // alef with madda / hamza above / hamza below / wasla -> bare alef
      0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627,
      // alef maqsura -> ya
      0x0649 => 0x064A,
      // ta marbuta -> ha
      0x0629 => 0x0647,
      // hamza on waw -> waw, hamza on ya -> ya
      0x0624 => 0x0648,
      0x0626 => 0x064A,
      // Arabic-Indic digits -> ASCII
      >= 0x0660 && <= 0x0669 => r - 0x0660 + 0x30,
      // Persian digits -> ASCII
      >= 0x06F0 && <= 0x06F9 => r - 0x06F0 + 0x30,
      _ => r,
    };
