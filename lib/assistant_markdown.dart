import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown({super.key, required this.data, this.onTapLink});

  final String data;
  final ValueChanged<String?>? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (_, href, _) => onTapLink?.call(href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: const TextStyle(color: Color(0xFF202235), fontSize: 15, height: 1.5),
        code: const TextStyle(
          color: Color(0xFF403582),
          fontFamily: 'monospace',
          backgroundColor: Color(0xFFF1EFFB),
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFFF5F4F8),
          borderRadius: BorderRadius.circular(10),
        ),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFF6558D8), width: 3)),
        ),
      ),
    );
  }
}
