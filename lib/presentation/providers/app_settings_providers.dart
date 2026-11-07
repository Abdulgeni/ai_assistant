import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User language override. Null means "follow the device".
/// In-memory only for now; persistence arrives with the settings module.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void setLocale(Locale? locale) {
    state = locale;
  }
}

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
