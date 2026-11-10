import 'dart:async';

import 'package:ai_assistant/core/localization/force_ltr.dart';
import 'package:ai_assistant/core/localization/l10n.dart';
import 'package:ai_assistant/core/theme/app_theme.dart';
import 'package:ai_assistant/core/theme/app_tokens.dart';
import 'package:ai_assistant/core/theme/app_typography.dart';
import 'package:ai_assistant/core/theme/widgets/pressable.dart';
import 'package:ai_assistant/presentation/providers/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

/// A fenced code block: language label, copy button, horizontally scrolling
/// selectable code. Always left-to-right, even inside an Arabic message.
class CodeBlock extends ConsumerStatefulWidget {
  const CodeBlock({required this.code, this.language = '', super.key});

  final String code;
  final String language;

  @override
  ConsumerState<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends ConsumerState<CodeBlock> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await ref.read(platformActionsProvider).copyText(widget.code);
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(AppChat.copiedFeedback, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final AppLocalizations l10n = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;

    return ForceLtr(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.codeBackground,
          borderRadius: const BorderRadiusDirectional.all(
            Radius.circular(AppRadii.md),
          ),
          border: Border.all(color: palette.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.language,
                      style: text.labelMedium?.copyWith(color: palette.onCode),
                    ),
                  ),
                  Pressable(
                    semanticLabel: l10n.copyCode,
                    haptic: PressHaptic.selection,
                    onPressed: () => unawaited(_copy()),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Icon(
                        _copied
                            ? Icons.check_rounded
                            : Icons.content_copy_rounded,
                        size: AppSizes.iconSm,
                        color: palette.onCode,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.md,
                end: AppSpacing.md,
                bottom: AppSpacing.md,
              ),
              child: SelectableText(
                widget.code,
                style: AppTypography.code(color: palette.onCode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders fenced code blocks as [CodeBlock]; inline code keeps the default
/// styling (returns null).
///
/// A block is recognised by a `language-xxx` class, or by a newline in its
/// text (fenced blocks always end with one). This depends on how
/// flutter_markdown_plus calls element builders; `markdown_content_test.dart`
/// pins the behavior, so a package change shows up as a failing test.
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String? className = element.attributes['class'];
    final bool isBlock =
        className != null || element.textContent.contains('\n');
    if (!isBlock) return null;

    final String language =
        className != null && className.startsWith('language-')
            ? className.substring('language-'.length)
            : '';
    return SizedBox(
      width: double.infinity,
      child: CodeBlock(code: element.textContent.trimRight(), language: language),
    );
  }
}
