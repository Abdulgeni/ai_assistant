import 'package:ai_assistant/domain/entities/voice_state.dart';

String _normalizeLocale(String id) => id.toLowerCase().replaceAll('-', '_');

/// The platform's own id for [requested], or null. Matches `ar_SA` against
/// `ar-SA` case-insensitively, then falls back to any id with the same
/// language (so `ar_SA` finds `ar_AE` when that is all the device has).
String? matchLocaleId(String requested, List<String> available) {
  final String wanted = _normalizeLocale(requested);
  for (final String id in available) {
    if (_normalizeLocale(id) == wanted) return id;
  }
  final String language = wanted.split('_').first;
  for (final String id in available) {
    if (_normalizeLocale(id).split('_').first == language) return id;
  }
  return null;
}

/// One status from several permissions (iOS needs microphone AND speech).
/// Granted only if all are; otherwise the most severe wins. An empty list is
/// treated as denied: there is no evidence of permission.
VoicePermissionStatus combinePermissionStatuses(
  List<VoicePermissionStatus> statuses,
) {
  if (statuses.isEmpty) return VoicePermissionStatus.denied;
  if (statuses.every((VoicePermissionStatus s) => s == VoicePermissionStatus.granted)) {
    return VoicePermissionStatus.granted;
  }
  if (statuses.contains(VoicePermissionStatus.permanentlyDenied)) {
    return VoicePermissionStatus.permanentlyDenied;
  }
  if (statuses.contains(VoicePermissionStatus.restricted)) {
    return VoicePermissionStatus.restricted;
  }
  return VoicePermissionStatus.denied;
}

enum RecognizerErrorKind { noSpeech, permission, busy, language, other }

/// Classifies a platform error code. Matching is by substring because the
/// exact code strings differ between Android and iOS and are not documented
/// as a stable list; unknown codes are [RecognizerErrorKind.other].
RecognizerErrorKind mapRecognizerError(String message) {
  final String m = message.toLowerCase();
  if (m.contains('no_match') || m.contains('speech_timeout')) {
    return RecognizerErrorKind.noSpeech;
  }
  if (m.contains('permission')) return RecognizerErrorKind.permission;
  if (m.contains('busy')) return RecognizerErrorKind.busy;
  if (m.contains('language')) return RecognizerErrorKind.language;
  return RecognizerErrorKind.other;
}

const Set<int> _sentenceEnders = <int>{
  0x2E, // .
  0x21, // !
  0x3F, // ?
  0x2026, // …
  0x061F, // ؟
  0x3002, // 。
  0x0A, // newline
};

bool _isLead(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isTrail(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

bool _isWhitespace(int unit) =>
    unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;

/// Splits [text] into chunks of at most [maxLength] UTF-16 units for the
/// synthesizer (Android refuses very long input). Prefers the last sentence
/// end in the window, then the last whitespace, then a hard cut; never splits
/// a surrogate pair. Blank input yields no chunks.
List<String> splitForSynthesis(String text, {int maxLength = 3000}) {
  assert(maxLength >= 2, 'maxLength must allow a surrogate pair');
  final List<String> chunks = <String>[];
  var rest = text.trim();
  while (rest.length > maxLength) {
    var cut = -1;
    for (var i = maxLength - 1; i >= 0; i--) {
      if (_sentenceEnders.contains(rest.codeUnitAt(i))) {
        cut = i + 1;
        break;
      }
    }
    if (cut < 0) {
      for (var i = maxLength - 1; i > 0; i--) {
        if (_isWhitespace(rest.codeUnitAt(i))) {
          cut = i + 1;
          break;
        }
      }
    }
    if (cut < 0) cut = maxLength;
    if (cut > 0 &&
        cut < rest.length &&
        _isTrail(rest.codeUnitAt(cut)) &&
        _isLead(rest.codeUnitAt(cut - 1))) {
      cut--;
    }
    final String chunk = rest.substring(0, cut).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    rest = rest.substring(cut).trimLeft();
  }
  if (rest.isNotEmpty) chunks.add(rest);
  return chunks;
}
