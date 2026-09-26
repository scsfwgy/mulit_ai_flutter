import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/assistant_markdown.dart';

void main() {
  testWidgets('assistant reply renders Markdown and keeps links interactive', (
    tester,
  ) async {
    String? tappedLink;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantMarkdown(
              data:
                  '# 标题\n\n**重点** 与 [链接](https://example.com)'
                  '\n\n- 第一项\n- 第二项\n\n```dart\nprint("ok");\n```',
              onTapLink: (href) => tappedLink = href,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('标题', findRichText: true), findsWidgets);
    expect(find.textContaining('重点', findRichText: true), findsWidgets);
    expect(find.textContaining('第一项', findRichText: true), findsWidgets);
    expect(
      find.textContaining('print("ok");', findRichText: true),
      findsWidgets,
    );

    final linkText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .firstWhere(
          (text) => text.textSpan?.toPlainText().contains('链接') ?? false,
        );
    final link = _linkSpan(linkText.textSpan!);
    expect(link?.recognizer, isA<TapGestureRecognizer>());
    (link!.recognizer! as TapGestureRecognizer).onTap!();
    expect(tappedLink, 'https://example.com');
  });
}

TextSpan? _linkSpan(InlineSpan span) {
  if (span is! TextSpan) return null;
  if (span.text == '链接' && span.recognizer != null) return span;
  for (final child in span.children ?? <InlineSpan>[]) {
    final link = _linkSpan(child);
    if (link != null) return link;
  }
  return null;
}
