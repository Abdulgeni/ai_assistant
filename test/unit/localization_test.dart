import 'dart:convert';
import 'dart:io';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/locale_support.dart';
import 'package:ai_assistant/domain/entities/stream_event.dart';
import 'package:ai_assistant/domain/entities/voice_state.dart';
import 'package:ai_assistant/presentation/l10n/failure_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readArb(String name) {
  final String raw =
      File('lib/core/localization/arb/$name').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

Iterable<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((String k) => !k.startsWith('@'));

final RegExp _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)[,}]');

Set<String> _placeholders(String message) => _placeholder
    .allMatches(message)
    .map((RegExpMatch m) => m.group(1)!)
    .toSet();

void main() {
  group('ARB files', () {
    final Map<String, dynamic> en = _readArb('app_en.arb');
    final Map<String, dynamic> ar = _readArb('app_ar.arb');

    test('Arabic has exactly the English message keys', () {
      expect(_messageKeys(ar).toSet(), _messageKeys(en).toSet());
    });

    test('placeholders match per message', () {
      for (final String key in _messageKeys(en)) {
        if (key.startsWith('@@')) continue;
        expect(
          _placeholders(ar[key] as String),
          _placeholders(en[key] as String),
          reason: 'placeholder mismatch in "$key"',
        );
      }
    });

    test('Arabic plural covers every CLDR category', () {
      final String plural = ar['sourcesCount'] as String;
      for (final String category in <String>[
        '=0',
        '=1',
        '=2',
        'few{',
        'many{',
        'other{',
      ]) {
        expect(plural, contains(category));
      }
    });
  });

  group('plurals', () {
    final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    test('Arabic: zero, one, two are exact words', () {
      expect(ar.sourcesCount(0), 'لا توجد مصادر');
      expect(ar.sourcesCount(1), 'مصدر واحد');
      expect(ar.sourcesCount(2), 'مصدران');
    });

    // Digit-agnostic: whether gen_l10n renders {count} with Latin or
    // Arabic-Indic digits is verified on a device, not assumed here.
    test('Arabic: 3-10 few, 11-99 many, 100+ other', () {
      expect(ar.sourcesCount(5), matches(RegExp(r'^[0-9٠-٩]+ مصادر$')));
      expect(ar.sourcesCount(11), endsWith('مصدرًا'));
      expect(ar.sourcesCount(99), endsWith('مصدرًا'));
      expect(ar.sourcesCount(100), matches(RegExp(r'^[0-9٠-٩]+ مصدر$')));
      expect(ar.sourcesCount(111), endsWith('مصدرًا'));
    });

    test('English: none, one, many', () {
      expect(en.sourcesCount(0), 'No sources');
      expect(en.sourcesCount(1), '1 source');
      expect(en.sourcesCount(2), '2 sources');
    });
  });

  group('failure messages', () {
    for (final Locale locale in AppLocalizations.supportedLocales) {
      final AppLocalizations l10n = lookupAppLocalizations(locale);

      test('every StreamFailureCode has text in ${locale.languageCode}', () {
        for (final StreamFailureCode code in StreamFailureCode.values) {
          expect(streamFailureMessage(l10n, code).trim(), isNotEmpty);
        }
      });

      test('every VoiceFailureCode has text in ${locale.languageCode}', () {
        for (final VoiceFailureCode code in VoiceFailureCode.values) {
          expect(voiceFailureMessage(l10n, code).trim(), isNotEmpty);
        }
      });
    }

    test('Arabic messages are translated, not copied from English', () {
      final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      for (final StreamFailureCode code in StreamFailureCode.values) {
        expect(
          streamFailureMessage(ar, code),
          isNot(streamFailureMessage(en, code)),
        );
      }
    });
  });

  group('resolveSupportedLocale', () {
    const List<Locale> supported = <Locale>[Locale('ar'), Locale('en')];

    test('uses the first supported device language', () {
      expect(
        resolveSupportedLocale(
          const <Locale>[Locale('fr'), Locale('en', 'US')],
          supported,
        ),
        const Locale('en'),
      );
    });

    test('matches on language code only', () {
      expect(
        resolveSupportedLocale(const <Locale>[Locale('ar', 'MA')], supported),
        const Locale('ar'),
      );
    });

    test('falls back to Arabic when nothing is supported', () {
      expect(
        resolveSupportedLocale(const <Locale>[Locale('fr')], supported),
        AppLocales.fallback,
      );
    });

    test('falls back to Arabic for null or empty device locales', () {
      expect(resolveSupportedLocale(null, supported), AppLocales.fallback);
      expect(
        resolveSupportedLocale(const <Locale>[], supported),
        AppLocales.fallback,
      );
    });
  });

  group('numerals', () {
    test('Latin to Arabic-Indic', () {
      expect(convertDigits('2025', NumeralSystem.arabicIndic), '٢٠٢٥');
    });

    test('mixed text keeps non-digits', () {
      expect(
        convertDigits('Room 12:30', NumeralSystem.arabicIndic),
        'Room ١٢:٣٠',
      );
    });

    test('Arabic-Indic and Persian digits to Latin', () {
      expect(convertDigits('٢٠٢٥', NumeralSystem.latin), '2025');
      expect(convertDigits('۲۰۲۵', NumeralSystem.latin), '2025');
    });

    test('is idempotent', () {
      const String once = '١٢٣';
      expect(convertDigits(once, NumeralSystem.arabicIndic), once);
    });

    test('localizeDigits follows the locale', () {
      expect(localizeDigits('12', const Locale('ar')), '١٢');
      expect(localizeDigits('١٢', const Locale('en')), '12');
    });
  });
}
