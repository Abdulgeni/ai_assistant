import 'dart:async';

import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/localization/locale_support.dart';
import 'package:ai_assistant/core/platform/link_dialog.dart';
import 'package:ai_assistant/core/platform/platform_actions.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/domain/entities/chat_message.dart';
import 'package:flutter/material.dart';

/// The citations for an answer. A source opens only if its link passes
/// [parseWebLink] (and then only after confirmation); otherwise it is listed
/// without a link.
Future<void> showSourcesSheet({
  required BuildContext context,
  required PlatformActions actions,
  required List<SourceReference> sources,
}) {
  final AppLocalizations l10n = context.l10n;
  final Locale locale = Localizations.localeOf(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height *
            AppChat.sheetMaxHeightFraction,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.lg,
                end: AppSpacing.lg,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                l10n.sourcesTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sources.length,
                itemBuilder: (BuildContext context, int index) {
                  final SourceReference source = sources[index];
                  final bool hasLink = parseWebLink(source.uri) != null;
                  return ListTile(
                    leading: Text(localizeDigits('${index + 1}', locale)),
                    title: Text(
                      source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: source.snippet == null
                        ? null
                        : Text(
                            source.snippet!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing:
                        hasLink ? const Icon(Icons.open_in_new_rounded) : null,
                    onTap: hasLink
                        ? () => unawaited(
                              confirmAndOpenLink(
                                context: sheetContext,
                                actions: actions,
                                href: source.uri,
                              ),
                            )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
