import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/provider/api_key_help.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all text presets point to their own credential console', () {
    expect(
      textApiKeyUrls.keys.toSet(),
      providerPresets.map((p) => p.id).toSet(),
    );
    for (final preset in providerPresets) {
      expect(
        textApiKeyUrlForEndpoint(preset.baseUrl),
        textApiKeyUrls[preset.id],
      );
    }
    for (final endpoint in [
      'https://api.example.com/v1',
      'https://api.openai.com.example.com/v1',
      'https://api.openai.com@evil.example/v1',
      'http://api.openai.com/v1',
      'not a URL',
    ]) {
      expect(textApiKeyUrlForEndpoint(endpoint), isNull);
    }
  });

  test('voice credential links distinguish speech from text services', () {
    expect(
      voiceApiKeyUrlForEndpoint(VoiceProtocol.deepseek, deepSeekVoiceBaseUrl),
      textApiKeyUrls['deepseek'],
    );
    expect(
      voiceApiKeyUrlForEndpoint(
        VoiceProtocol.deepseek,
        'https://custom.example/v1',
      ),
      isNull,
    );
    expect(
      voiceApiKeyUrlForEndpoint(
        VoiceProtocol.mimo,
        'https://api.xiaomimimo.com/v1',
      ),
      mimoApiKeyUrl,
    );
    expect(
      voiceApiKeyUrlForEndpoint(
        VoiceProtocol.doubao,
        'https://openspeech.bytedance.com',
      ),
      doubaoVoiceApiKeyUrl,
    );
    expect(doubaoVoiceApiKeyUrl, isNot(textApiKeyUrls['doubao']));
    expect(
      voiceApiKeyUrlForEndpoint(
        VoiceProtocol.openAi,
        'https://api.openai.com/v1',
      ),
      textApiKeyUrls['openai'],
    );
    expect(
      voiceApiKeyUrlForEndpoint(
        VoiceProtocol.openAi,
        'https://custom.example/v1',
      ),
      isNull,
    );
    expect(
      voiceApiKeyUrlForEndpoint(
        VoiceProtocol.doubao,
        'https://ark.cn-beijing.volces.com/api/v3',
      ),
      isNull,
    );
  });

  testWidgets('provider guidance follows edited form and JSON endpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderEditor(
          preset: providerPresets.firstWhere((p) => p.id == 'deepseek'),
        ),
      ),
    );
    expect(find.text('platform.deepseek.com/api_keys'), findsOneWidget);
    final endpoint = find.byType(CupertinoTextField).at(1);
    await tester.enterText(endpoint, 'https://custom.example/v1');
    await tester.pump();
    expect(find.text('申请 API Key'), findsNothing);
    expect(find.text('API Key 获取教程'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField),
      jsonEncode({
        'name': 'OpenAI',
        'protocol': 'openai',
        'baseUrl': 'https://api.openai.com/v1',
        'model': 'example',
        'apiKey': '',
      }),
    );
    await tester.pump();
    expect(find.text('platform.openai.com/api-keys'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), '{invalid');
    await tester.pump();
    expect(find.text('申请 API Key'), findsNothing);
  });

  testWidgets('About opens the exact public tutorial in an external browser', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(launcher, (call) async {
      final args = call.arguments as Map;
      opened = args['url'] as String;
      expect(args['useWebView'], false);
      expect(args['headers'], isEmpty);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API Key 获取教程'));
    await tester.pumpAndSettle();
    expect(opened, apiKeyTutorialUrl);
    expect(tester.takeException(), isNull);
  });
}
