import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/locale_support.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:ai_assistant/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget: theme, localization, and text direction in one place.
///
/// Text direction comes from the resolved locale via
/// `GlobalWidgetsLocalizations`, which the generated
/// `AppLocalizations.localizationsDelegates` includes. Forgetting that delegate
/// is the classic reason an Arabic app stays left-to-right.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale? localeOverride = ref.watch(localeProvider);
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      onGenerateTitle: (BuildContext context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: localeOverride,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      localeListResolutionCallback: resolveSupportedLocale,
      home: const ChatScreen(),
    );
  }
}
