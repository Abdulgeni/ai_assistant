import 'dart:async';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/platform/platform_actions.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _MessageAction { copy, share, regenerate }

/// Bottom sheet of actions for one message: copy, share, and (for the newest
/// assistant message) regenerate. [context] should belong to the message's
/// bubble, so the iPad share popover anchors to it.
Future<void> showMessageActions({
  required BuildContext context,
  required PlatformActions actions,
  required ChatMessage message,
  required bool canRegenerate,
  required VoidCallback onRegenerate,
}) async {
  final AppLocalizations l10n = context.l10n;
  final RenderBox? box = context.findRenderObject() as RenderBox?;
  final Rect? origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  unawaited(HapticFeedback.mediumImpact());

  final _MessageAction? chosen = await showModalBottomSheet<_MessageAction>(
    context: context,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(l10n.copy),
            onTap: () => Navigator.of(sheetContext).pop(_MessageAction.copy),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(l10n.share),
            onTap: () => Navigator.of(sheetContext).pop(_MessageAction.share),
          ),
          if (canRegenerate)
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(l10n.regenerate),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_MessageAction.regenerate),
            ),
        ],
      ),
    ),
  );

  switch (chosen) {
    case null:
      return;
    case _MessageAction.copy:
      await actions.copyText(message.content);
      messenger.showSnackBar(SnackBar(content: Text(l10n.copied)));
    case _MessageAction.share:
      await actions.shareText(message.content, origin: origin);
    case _MessageAction.regenerate:
      onRegenerate();
  }
}
