import 'package:flutter/widgets.dart';

/// Forces left-to-right layout for content that must never be reordered inside
/// an RTL paragraph: phone numbers, IDs, codes, URLs, code blocks.
class ForceLtr extends StatelessWidget {
  const ForceLtr({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: child);
}
