import 'dart:math';

import 'package:ai_assistant/data/voice/voice_text_utils.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';
import 'package:flutter_test/flutter_test.dart';

bool _hasLoneSurrogate(String text) {
  final List<int> units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final int u = units[i];
    final bool lead = u >= 0xD800 && u <= 0xDBFF;
    final bool trail = u >= 0xDC00 && u <= 0xDFFF;
    if (lead && (i + 1 >= units.length || units[i + 1] < 0xDC00 || units[i + 1] > 0xDFFF)) {
      return true;
    }
    if (trail && (i == 0 || units[i - 1] < 0xD800 || units[i - 1] > 0xDBFF)) {
      return true;
    }
  }
  return false;
}

void main() {
  group('matchLocaleId', () {
    test('matches across separators and case', () {
      expect(matchLocaleId('ar_SA', <String>['en_US', 'ar-SA']), 'ar-SA');
      expect(matchLocaleId('AR_sa', <String>['ar_SA']), 'ar_SA');
    });

    test('falls back to the same language', () {
      expect(matchLocaleId('ar_SA', <String>['en_US', 'ar_AE', 'ar_EG']), 'ar_AE');
      expect(matchLocaleId('ar', <String>['en', 'ar_EG']), 'ar_EG');
    });

    test('returns null when nothing matches', () {
      expect(matchLocaleId('ar_SA', <String>['en_US', 'fr_FR']), isNull);
      expect(matchLocaleId('ar', <String>[]), isNull);
    });
  });

  group('combinePermissionStatuses', () {
    const VoicePermissionStatus g = VoicePermissionStatus.granted;
    const VoicePermissionStatus d = VoicePermissionStatus.denied;
    const VoicePermissionStatus p = VoicePermissionStatus.permanentlyDenied;
    const VoicePermissionStatus r = VoicePermissionStatus.restricted;

    test('granted only when everything is', () {
      expect(combinePermissionStatuses(<VoicePermissionStatus>[g, g]), g);
      expect(combinePermissionStatuses(<VoicePermissionStatus>[g, d]), d);
    });

    test('the most severe status wins', () {
      expect(combinePermissionStatuses(<VoicePermissionStatus>[d, p]), p);
      expect(combinePermissionStatuses(<VoicePermissionStatus>[g, r, d]), r);
    });

    test('an empty list is denied', () {
      expect(combinePermissionStatuses(<VoicePermissionStatus>[]), d);
    });
  });

  group('mapRecognizerError', () {
    const Map<String, RecognizerErrorKind> expected = <String, RecognizerErrorKind>{
      'error_no_match': RecognizerErrorKind.noSpeech,
      'error_speech_timeout': RecognizerErrorKind.noSpeech,
      'error_insufficient_permissions': RecognizerErrorKind.permission,
      'error_recognizer_busy': RecognizerErrorKind.busy,
      'error_language_not_supported': RecognizerErrorKind.language,
      'error_network': RecognizerErrorKind.other,
      'error_unknown': RecognizerErrorKind.other,
    };
    for (final MapEntry<String, RecognizerErrorKind> e in expected.entries) {
      test('${e.key} -> ${e.value.name}', () {
        expect(mapRecognizerError(e.key), e.value);
      });
    }
  });

  group('splitForSynthesis', () {
    test('short text is a single chunk; blank text yields none', () {
      expect(splitForSynthesis('مرحبا بك.'), <String>['مرحبا بك.']);
      expect(splitForSynthesis('  \n '), isEmpty);
    });

    test('prefers sentence boundaries, including the Arabic question mark', () {
      expect(
        splitForSynthesis('جملة أولى. جملة ثانية؟ جملة ثالثة!', maxLength: 20),
        <String>['جملة أولى.', 'جملة ثانية؟', 'جملة ثالثة!'],
      );
    });

    test('falls back to whitespace, then to a hard cut', () {
      expect(splitForSynthesis('aaa bbb ccc ddd', maxLength: 8), <String>['aaa bbb', 'ccc ddd']);
      expect(splitForSynthesis('abcdefghij', maxLength: 4), <String>['abcd', 'efgh', 'ij']);
    });

    test('never splits an emoji surrogate pair', () {
      final String text = '😀' * 10;
      for (final String chunk in splitForSynthesis(text, maxLength: 5)) {
        expect(_hasLoneSurrogate(chunk), isFalse, reason: chunk);
      }
    });

    test('random texts: size cap, no empty chunks, no lone surrogates, content kept', () {
      final Random random = Random(5);
      const List<String> pieces = <String>[
        'abc ', 'def. ', 'ويا ', 'مرحبا؟ ', '! ', '\n', 'ثم ', '😀', '👋🏽', 'x',
      ];
      for (var trial = 0; trial < 1500; trial++) {
        final String text = <String>[
          for (var i = 0; i < random.nextInt(200); i++) pieces[random.nextInt(pieces.length)],
        ].join();
        final int max = <int>[5, 8, 20, 50][random.nextInt(4)];
        final List<String> chunks = splitForSynthesis(text, maxLength: max);
        for (final String chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(max));
          expect(chunk.trim(), isNotEmpty);
          expect(_hasLoneSurrogate(chunk), isFalse);
        }
        expect(
          chunks.join().replaceAll(RegExp(r'\s'), ''),
          text.replaceAll(RegExp(r'\s'), ''),
        );
      }
    });
  });
}
