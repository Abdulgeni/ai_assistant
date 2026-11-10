import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// Direction of [text] from its first strongly-directional character, so a
/// message keeps its direction as it streams in. Text with no strong character
/// yet (digits, punctuation, empty) uses [fallback].
TextDirection textDirectionFor(String text, {required TextDirection fallback}) {
  if (Bidi.startsWithRtl(text)) return TextDirection.rtl;
  if (Bidi.startsWithLtr(text)) return TextDirection.ltr;
  return fallback;
}
