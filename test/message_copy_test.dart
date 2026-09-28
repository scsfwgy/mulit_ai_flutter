import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/message_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formatted copy sends rich HTML with readable plain text', () async {
    const channel = MethodChannel('between_models/clipboard');
    MethodCall? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          copied = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await copyMessage(
      '**Bold** [site](https://example.com)',
      MessageCopyFormat.formatted,
    );
    expect(copied?.method, 'setHtml');
    final payload = copied?.arguments as Map;
    expect(payload['plain'], 'Bold site');
    expect(payload['html'], contains('<strong>Bold</strong>'));
    expect(payload['html'], contains('<a href="https://example.com">site</a>'));
    expect(visibleCharacterCount(payload['plain'] as String), 8);

    await copyMessage(
      '**literal** <user>',
      MessageCopyFormat.formatted,
      renderMarkdown: false,
    );
    final userPayload = copied?.arguments as Map;
    expect(userPayload['plain'], '**literal** <user>');
    expect(userPayload['html'], contains('&lt;user&gt;'));
  });

  test('source copy preserves Markdown markers', () async {
    MethodCall? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') copied = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await copyMessage('**Bold**', MessageCopyFormat.markdown);
    expect(copied?.method, 'Clipboard.setData');
    expect((copied?.arguments as Map)['text'], '**Bold**');
  });
}
