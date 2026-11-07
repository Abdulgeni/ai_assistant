import 'package:flutter/widgets.dart';

abstract final class AppLocales {
  static const Locale arabic = Locale('ar');
  static const Locale english = Locale('en');

  /// Used when none of the device languages is supported.
  static const Locale fallback = arabic;
}

/// Picks the first device language we support (matching on language code only,
/// so `ar_SA` and `ar_MA` both get `ar`). Falls back to [AppLocales.fallback].
/// Pure function: used as MaterialApp's `localeListResolutionCallback`.
Locale resolveSupportedLocale(
  List<Locale>? deviceLocales,
  Iterable<Locale> supportedLocales,
) {
  for (final Locale device in deviceLocales ?? const <Locale>[]) {
    for (final Locale supported in supportedLocales) {
      if (supported.languageCode == device.languageCode) return supported;
    }
  }
  return AppLocales.fallback;
}

enum NumeralSystem { latin, arabicIndic }

/// Product decision, single switch: Arabic UI shows Arabic-Indic digits.
/// Change this one function to prefer Western digits everywhere.
NumeralSystem numeralSystemFor(Locale locale) =>
    locale.languageCode == 'ar' ? NumeralSystem.arabicIndic : NumeralSystem.latin;

/// Rewrites every digit (Latin, Arabic-Indic, Persian) in [input] into
/// [system]. Deterministic, so it does not depend on intl's per-locale digit
/// data. Never apply it to IDs, codes, or phone numbers: wrap those in
/// `ForceLtr` and leave them as typed.
String convertDigits(String input, NumeralSystem system) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.runes) {
    final int? value = _digitValue(rune);
    if (value == null) {
      out.writeCharCode(rune);
    } else {
      out.writeCharCode(
        system == NumeralSystem.latin ? 0x30 + value : 0x0660 + value,
      );
    }
  }
  return out.toString();
}

String localizeDigits(String input, Locale locale) =>
    convertDigits(input, numeralSystemFor(locale));

int? _digitValue(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
  if (rune >= 0x0660 && rune <= 0x0669) return rune - 0x0660;
  if (rune >= 0x06F0 && rune <= 0x06F9) return rune - 0x06F0;
  return null;
}
