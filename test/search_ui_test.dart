import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/app_preferences.dart';
import 'package:mulit_ai_flutter/search_service.dart';
import 'package:mulit_ai_flutter/search_settings_screen.dart';
import 'package:mulit_ai_flutter/search_sources.dart';
import 'package:mulit_ai_flutter/settings_screen.dart';
import 'package:mulit_ai_flutter/ios_style.dart';

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  for (final scenario in [
    'missing provider',
    'missing key',
    'configured',
    'configured after setup',
  ]) {
    testWidgets('message search switch checks $scenario before enabling', (
      tester,
    ) async {
      final values = <String, String>{};
      final secrets = <String, String>{};
      if (scenario == 'missing key' || scenario == 'configured') {
        const provider = SearchProviderConfig(
          id: 'test-search',
          name: 'Tavily',
          service: SearchService.tavily,
          endpoint: 'https://api.tavily.com/search',
        );
        values['search_providers'] = jsonEncode([provider.toJson()]);
        values['search_provider_id'] = provider.id;
        if (scenario == 'configured') {
          secrets['search_${provider.id}'] = 'fake-key';
        }
      }
      const database = MethodChannel('com.tekartik.sqflite');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(database, (call) async {
        if (call.method == 'getDatabasesPath') return '/test';
        if (call.method == 'openDatabase') return 1;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final sql = args['sql'] as String;
        final params = args['arguments'] as List? ?? [];
        if (call.method == 'query') {
          if (sql == 'PRAGMA user_version') {
            return [
              {'user_version': 5},
            ];
          }
          final key = params.single;
          return values.containsKey(key)
              ? [
                  {'value': values[key]},
                ]
              : [];
        }
        if (call.method == 'insert') {
          values[params[0] as String] = params[1] as String;
          return 1;
        }
        if (call.method == 'execute') return null;
        throw StateError('Unexpected database operation: ${call.method}');
      });
      messenger.setMockMethodCallHandler(
        secure,
        (call) async => secrets[(call.arguments as Map)['key']],
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(database, null);
        messenger.setMockMethodCallHandler(secure, null);
      });
      await tester.pumpWidget(const MaterialApp(home: MessageSettingsScreen()));
      await tester.pumpAndSettle();
      final toggle = find.descendant(
        of: find.ancestor(of: find.text('联网搜索'), matching: find.byType(IosRow)),
        matching: find.byType(CupertinoSwitch),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      if (scenario == 'configured') {
        expect(values['search_enabled'], '1');
        expect(tester.widget<CupertinoSwitch>(toggle).value, true);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(values['search_enabled'], '0');
      } else {
        expect(find.byType(SearchSettingsScreen), findsOneWidget);
        expect(values['search_enabled'], isNull);
        if (scenario == 'configured after setup') {
          const provider = SearchProviderConfig(
            id: 'new-search',
            name: 'Tavily',
            service: SearchService.tavily,
            endpoint: 'https://api.tavily.com/search',
          );
          values['search_providers'] = jsonEncode([provider.toJson()]);
          values['search_provider_id'] = provider.id;
          secrets['search_${provider.id}'] = 'fake-key';
        }
        await tester.tap(find.byIcon(CupertinoIcons.back));
        await tester.pumpAndSettle();
        expect(
          tester.widget<CupertinoSwitch>(toggle).value,
          scenario == 'configured after setup',
        );
        if (scenario == 'configured after setup') {
          expect(values['search_enabled'], '1');
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('search presets update endpoint and clear credentials', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(launcher, (call) async {
      expect(call.method, 'launch');
      final args = call.arguments as Map;
      opened.add(args['url'] as String);
      expect(args['useWebView'], false);
      expect(args['headers'], isEmpty);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
    await tester.pumpWidget(const MaterialApp(home: SearchServiceEditor()));
    expect(find.text('博查'), findsNWidgets(2));
    expect(find.text('https://api.bochaai.com/v1/web-search'), findsOneWidget);
    expect(find.textContaining('模型 ID'), findsNothing);
    final key = find.byType(CupertinoTextField).last;
    await tester.enterText(key, 'fake-key');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(find.text('按量付费'), findsOneWidget);
    await tester.tap(find.text('申请 API Key'));
    await tester.pumpAndSettle();
    expect(opened.last, 'https://open.bochaai.com/api-keys');
    await tester.tap(find.text('搜索服务类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tavily'));
    await tester.pumpAndSettle();
    expect(find.text('https://api.tavily.com/search'), findsOneWidget);
    expect(tester.widget<CupertinoTextField>(key).controller!.text, isEmpty);
    expect(tester.widget<CupertinoTextField>(key).obscureText, true);
    expect(find.text('深入搜索'), findsOneWidget);
    expect(find.textContaining('每月 1,000 免费积分'), findsOneWidget);
    await tester.tap(find.text('申请 API Key'));
    await tester.pumpAndSettle();
    expect(opened.last, 'https://app.tavily.com/');
    await tester.tap(find.text('查看价格与免费额度'));
    await tester.pumpAndSettle();
    expect(opened.last, 'https://docs.tavily.com/documentation/api-credits');
    await tester.tap(find.text('搜索服务类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exa'));
    await tester.pumpAndSettle();
    expect(find.text('https://api.exa.ai/search'), findsOneWidget);
    expect(find.textContaining('每月 10 美元免费额度'), findsOneWidget);
    await tester.tap(find.text('申请 API Key'));
    await tester.pumpAndSettle();
    expect(opened.last, 'https://dashboard.exa.ai/api-keys');
    await tester.tap(find.text('查看价格与免费额度'));
    await tester.pumpAndSettle();
    expect(opened.last, 'https://exa.ai/pricing');
  });

  testWidgets('saved sources expand, open exact URLs and fit narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 270,
            child: SearchSources(
              sources: [
                SearchSource(
                  title: '很长的网页标题' * 30,
                  url: 'https://example.com/source',
                  excerpt: '资料',
                ),
              ],
              onOpen: (url) => opened = url,
            ),
          ),
        ),
      ),
    );
    expect(find.text('example.com'), findsNothing);
    await tester.tap(find.text('搜索来源 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsOneWidget);
    await tester.tap(find.text('example.com'));
    expect(opened, 'https://example.com/source');
    expect(tester.takeException(), isNull);
  });

  test('search labels have English translations', () {
    final before = AppPreferences.instance.language;
    AppPreferences.instance.language = AppLanguage.en;
    try {
      expect(tr('联网搜索'), 'Web search');
      expect(tr('消息设置'), 'Message settings');
      expect(tr('正在搜索网页…'), 'Searching the web…');
      expect(tr('搜索来源'), 'Search sources');
      expect(tr('搜索请求失败（HTTP 401），请检查密钥、额度和接口地址。'), contains('HTTP 401'));
      expect(tr('未找到可用网页资料，请修改问题或关闭联网搜索。'), startsWith('No usable'));
    } finally {
      AppPreferences.instance.language = before;
    }
  });
}
