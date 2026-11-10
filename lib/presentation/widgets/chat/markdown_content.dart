import 'dart:async';

import 'package:ai_assistant/core/localization/text_direction.dart';
import 'package:ai_assistant/core/platform/link_dialog.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/app_typography.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:ai_assistant/presentation/widgets/chat/code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An assistant message rendered as Markdown (GitHub flavored; no inline
/// HTML), styled from the design tokens.
///
///  * The block takes its direction from its first strong character, so lists
///    and quotes lay out correctly for Arabic and English.
///  * Links are never followed silently: a tap shows the URL and asks first.
///  * Fenced code becomes a [CodeBlock] with a copy button.
class MarkdownContent extends ConsumerWidget {
  const MarkdownContent({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final ThemeData theme = Theme.of(context);
    final TextStyle base =
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(color: color);

    final MarkdownStyleSheet sheet =
        MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      h1: theme.textTheme.headlineSmall?.copyWith(color: color),
      h2: theme.textTheme.titleLarge?.copyWith(color: color),
      h3: theme.textTheme.titleMedium?.copyWith(color: color),
      h4: theme.textTheme.titleSmall?.copyWith(color: color),
      h5: theme.textTheme.titleSmall?.copyWith(color: color),
      h6: theme.textTheme.titleSmall?.copyWith(color: color),
      a: base.copyWith(
        color: palette.accent,
        decoration: TextDecoration.underline,
        decorationColor: palette.accent,
      ),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      code: AppTypography.code(color: palette.onCode)
          .copyWith(backgroundColor: palette.codeBackground),
      // The CodeBlock widget draws its own frame.
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      blockquote: base,
      blockquoteDecoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(
            color: palette.outlineStrong,
            width: AppChat.quoteBarWidth,
          ),
        ),
      ),
      listBullet: base,
      tableHead: base.copyWith(fontWeight: FontWeight.w700),
      tableBody: base,
      tableBorder: TableBorder.all(color: palette.outline),
      horizontalRuleDecoration: BoxDecoration(
        border: BorderDirectional(top: BorderSide(color: palette.outline)),
      ),
    );

    return Directionality(
      textDirection:
          textDirectionFor(text, fallback: Directionality.of(context)),
      child: MarkdownBody(
        data: text,
        styleSheet: sheet,
        softLineBreak: true,
        builders: <String, MarkdownElementBuilder>{'code': CodeBlockBuilder()},
        onTapLink: (String linkText, String? href, String title) {
          unawaited(
            confirmAndOpenLink(
              context: context,
              actions: ref.read(platformActionsProvider),
              href: href,
            ),
          );
        },
      ),
    );
  }
}
