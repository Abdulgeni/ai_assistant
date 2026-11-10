import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// Welcome screen for a conversation with no messages: a glowing orb, a
/// greeting, and tappable suggestions. Items fade and rise in, staggered
/// (instant under reduce-motion). Scrolls if the screen is short or text is
/// large.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.onSuggestion, super.key});

  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final palette = context.palette;
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> suggestions = <String>[
      l10n.suggestionSummarize,
      l10n.suggestionEmail,
      l10n.suggestionExplain,
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Reveal(
              order: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: palette.orbColors,
                  ),
                  boxShadow: AppShadows.glow(palette.orbA),
                ),
                child: const SizedBox.square(
                  dimension: AppChat.orbSize,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: AppSizes.iconLg,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Reveal(
              order: 1,
              child: Text(
                l10n.emptyTitle,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _Reveal(
              order: 2,
              child: Text(
                l10n.emptySubtitle,
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: palette.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Reveal(
              order: 3,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final String suggestion in suggestions)
                    _SuggestionChip(
                      label: suggestion,
                      onPressed: () => onSuggestion(suggestion),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final Duration duration = motion.reduceMotion
        ? Duration.zero
        : motion.fast + Duration(milliseconds: order * AppChat.revealStepMs);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: motion.standard,
      child: child,
      builder: (BuildContext context, double value, Widget? child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AppChat.entranceSlide),
          child: child,
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Pressable(
      onPressed: onPressed,
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
