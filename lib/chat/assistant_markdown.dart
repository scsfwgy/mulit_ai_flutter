import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:mulit_ai_flutter/ui/ios_style.dart';

class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown({
    super.key,
    required this.data,
    this.onTapLink,
    this.loadImages = true,
  });

  final String data;
  final bool loadImages;
  final ValueChanged<String?>? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: true,
      imageBuilder: loadImages
          ? null
          : (uri, title, alt) => Text(
              alt?.isNotEmpty == true ? alt! : uri.toString(),
              style: TextStyle(color: IosColors.secondary),
            ),
      onTapLink: (_, href, _) => onTapLink?.call(href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: TextStyle(color: IosColors.label, fontSize: 15, height: 1.5),
        code: TextStyle(
          color: IosColors.label,
          fontFamily: 'monospace',
          backgroundColor: IosColors.background,
        ),
        codeblockDecoration: BoxDecoration(
          color: IosColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: IosColors.blue, width: 3)),
        ),
      ),
    );
  }
}
