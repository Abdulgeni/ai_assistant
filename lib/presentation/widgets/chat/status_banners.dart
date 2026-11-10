import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Informational notices above the composer. Each is a live region, so screen
/// readers announce it when it appears. (Generation failures are shown on the
/// failed message itself, not here.)
class StatusBanners extends StatelessWidget {
  const StatusBanners({
    required this.configured,
    required this.otherChatBusy,
    required this.storageError,
    super.key,
  });

  final bool configured;
  final bool otherChatBusy;
  final bool storageError;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final List<Widget> banners = <Widget>[
      if (!configured)
        _Banner(icon: Icons.cloud_off_rounded, message: l10n.notConfigured),
      if (otherChatBusy)
        _Banner(icon: Icons.hourglass_top_rounded, message: l10n.otherChatBusy),
      if (storageError)
        _Banner(icon: Icons.sd_storage_rounded, message: l10n.storageWarning),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: banners),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: const BorderRadiusDirectional.all(
              Radius.circular(AppRadii.md),
            ),
            border: Border.all(color: palette.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: AppSizes.iconSm, color: palette.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
