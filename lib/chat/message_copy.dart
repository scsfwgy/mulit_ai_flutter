import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

enum MessageCopyFormat { markdown, formatted }

const _richClipboard = MethodChannel('between_models/clipboard');

String readableMarkdown(String source) {
  final buffer = StringBuffer();

  void visit(md.Node node) {
    if (node is md.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! md.Element) return;
    if (node.tag == 'br') {
      buffer.write('\n');
      return;
    }
    if (node.tag == 'img') {
      buffer.write(node.attributes['alt'] ?? '');
      return;
    }
    if (node.tag == 'li') buffer.write('• ');
    for (final child in node.children ?? <md.Node>[]) {
      visit(child);
    }
    if (node.tag == 'td' || node.tag == 'th') buffer.write('\t');
    if ({
      'p',
      'li',
      'pre',
      'blockquote',
      'tr',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    }.contains(node.tag)) {
      buffer.write('\n');
    }
  }

  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  for (final node in document.parse(source)) {
    visit(node);
    buffer.write('\n');
  }
  return buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

int visibleCharacterCount(String text) => text.runes
    .where((rune) => String.fromCharCode(rune).trim().isNotEmpty)
    .length;

Future<void> copyMessage(
  String source,
  MessageCopyFormat format, {
  bool renderMarkdown = true,
}) async {
  if (format == MessageCopyFormat.markdown) {
    await Clipboard.setData(ClipboardData(text: source));
    return;
  }
  final plain = renderMarkdown ? readableMarkdown(source) : source;
  final html = renderMarkdown
      ? md.markdownToHtml(
          source,
          extensionSet: md.ExtensionSet.gitHubFlavored,
          enableTagfilter: true,
        )
      : '<p>${const HtmlEscape().convert(source).replaceAll('\n', '<br>')}</p>';
  try {
    await _richClipboard.invokeMethod<void>('setHtml', {
      'plain': plain,
      'html': html,
    });
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: plain));
  } on PlatformException {
    await Clipboard.setData(ClipboardData(text: plain));
  }
}
