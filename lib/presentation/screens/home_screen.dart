import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/locale_support.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/app_background.dart';
import 'package:ai_assistant/core/theme/widgets/glass_surface.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/core/theme/widgets/skeleton.dart';
import 'package:ai_assistant/presentation/providers/app_settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-shell smoke screen. It exercises theme, localization, RTL mirroring,
/// the design primitives, and the settings providers. The chat module replaces
/// it with the real chat screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.contentMaxWidth,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    GlassSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(l10n.appTitle, style: text.titleLarge),
                          ),
                          Pressable(
                            semanticLabel: l10n.switchLanguage,
                            onPressed: () => _toggleLocale(context, ref),
                            child: const Icon(
                              Icons.translate_rounded,
                              size: AppSizes.iconMd,
                            ),
                          ),
                          Pressable(
                            semanticLabel: l10n.switchTheme,
                            onPressed: () => _toggleTheme(context, ref),
                            child: const Icon(
                              Icons.brightness_6_rounded,
                              size: AppSizes.iconMd,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(l10n.emptyTitle, style: text.headlineSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.emptySubtitle,
                      style: text.bodyLarge?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: <Widget>[
                        _SuggestionChip(label: l10n.suggestionSummarize),
                        _SuggestionChip(label: l10n.suggestionEmail),
                        _SuggestionChip(label: l10n.suggestionExplain),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      l10n.sourcesCount(12),
                      style: text.labelMedium?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SkeletonScope(
                      semanticLabel: l10n.loading,
                      child: const SkeletonText(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Pressable(
                      semanticLabel: l10n.startVoice,
                      haptic: PressHaptic.light,
                      onPressed: () {},
                      focusBorderRadius: const BorderRadiusDirectional.all(
                        Radius.circular(AppRadii.pill),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: palette.userBubbleGradient,
                          borderRadius: const BorderRadiusDirectional.all(
                            Radius.circular(AppRadii.pill),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Icon(
                            Icons.mic_rounded,
                            size: AppSizes.iconMd,
                            color: palette.onUserBubble,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _toggleLocale(BuildContext context, WidgetRef ref) {
  final Locale current = Localizations.localeOf(context);
  ref.read(localeProvider.notifier).setLocale(
        current.languageCode == 'ar' ? AppLocales.english : AppLocales.arabic,
      );
}

void _toggleTheme(BuildContext context, WidgetRef ref) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  ref
      .read(themeModeProvider.notifier)
      .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onPressed: () {},
      focusBorderRadius: const BorderRadiusDirectional.all(
        Radius.circular(AppRadii.pill),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: const BorderRadiusDirectional.all(
            Radius.circular(AppRadii.pill),
          ),
          border: Border.all(color: palette.outline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      ),
    );
  }
}
