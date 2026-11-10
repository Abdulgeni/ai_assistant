import 'package:ai_assistant/core/localization/force_ltr.dart';
import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/platform/platform_actions.dart';
import 'package:flutter/material.dart';

/// Shows the full URL and asks before opening it. Does nothing for links that
/// [parseWebLink] refuses.
Future<void> confirmAndOpenLink({
  required BuildContext context,
  required PlatformActions actions,
  required String? href,
}) async {
  final Uri? uri = parseWebLink(href);
  if (uri == null) return;
  final AppLocalizations l10n = context.l10n;

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(l10n.openLinkTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // URLs are left-to-right even inside an Arabic UI.
          ForceLtr(child: Text(uri.toString())),
          const SizedBox(height: 12),
          Text(l10n.openLinkBody),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.open),
        ),
      ],
    ),
  );
  if (confirmed == true) await actions.openUrl(uri);
}
