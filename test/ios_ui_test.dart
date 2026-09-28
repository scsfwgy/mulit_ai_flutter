import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mulit_ai_flutter/api_client.dart';
import 'package:mulit_ai_flutter/app_preferences.dart';
import 'package:mulit_ai_flutter/chat_more_menu.dart';
import 'package:mulit_ai_flutter/chat_loading_status.dart';
import 'package:mulit_ai_flutter/chat_message_meta.dart';
import 'package:mulit_ai_flutter/chat_model_selector.dart';
import 'package:mulit_ai_flutter/chat_model_title.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/ios_style.dart';
import 'package:mulit_ai_flutter/model_picker.dart';
import 'package:mulit_ai_flutter/provider_screen.dart';
import 'package:mulit_ai_flutter/privacy_screen.dart';
import 'package:mulit_ai_flutter/settings_screen.dart';

void main() {
  testWidgets('message details settings exposes each display switch', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: MessageInfoSettingsScreen()),
    );
    expect(find.byType(CupertinoSwitch), findsNWidgets(5));
    expect(find.text('首帧耗时'), findsOneWidget);
    expect(find.text('总耗时'), findsOneWidget);
    expect(find.text('Token 用量'), findsOneWidget);
    expect(find.text('字数'), findsOneWidget);
  });

  testWidgets('assistant details show request usage; user details do not', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatMessageMeta(
                assistant: true,
                content: '**你好**',
                providerName: 'OpenAI',
                providerPresetId: 'openai',
                modelId: 'example/model',
                firstTokenMs: 530,
                totalMs: 1800,
                inputTokens: 40,
                outputTokens: 12,
              ),
              ChatMessageMeta(
                assistant: false,
                content: '你好',
                providerName: 'DeepSeek',
                providerPresetId: 'deepseek',
                modelId: 'example/model',
              ),
              ChatMessageMeta(assistant: true, content: '旧消息'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('首帧 530ms'), findsOneWidget);
    expect(find.text('耗时 1.8s'), findsOneWidget);
    expect(find.text('输入 40'), findsOneWidget);
    expect(find.text('输出 12'), findsOneWidget);
    expect(find.text('2 字'), findsNWidgets(2));
    expect(find.text('example/model'), findsNWidgets(2));
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('3 字'), findsOneWidget);
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('settings exposes model, language, appearance, and about', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text('模型设置'), findsOneWidget);
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('换肤'));
    await tester.pumpAndSettle();
    expect(find.text('模式'), findsOneWidget);
    await tester.tap(find.text('模式'));
    await tester.pumpAndSettle();
    expect(find.text('白天'), findsOneWidget);
    expect(find.text('黑夜'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题色'));
    await tester.pumpAndSettle();
    expect(find.text('紫罗兰'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模型设置'));
    await tester.pumpAndSettle();
    expect(find.text('模型服务'), findsOneWidget);
    expect(find.text('提示词'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('开源许可'), findsOneWidget);
  });

  test(
    'English labels resolve without changing provider names or model IDs',
    () {
      final preferences = AppPreferences.instance;
      final previous = preferences.language;
      preferences.language = AppLanguage.en;
      try {
        expect(tr('模型服务'), 'Model services');
        expect(tr('claude-opus-4-6'), 'claude-opus-4-6');
      } finally {
        preferences.language = previous;
      }
    },
  );

  testWidgets('dark appearance changes shared surfaces and text colors', (
    tester,
  ) async {
    final preferences = AppPreferences.instance;
    final previous = preferences.appearance;
    try {
      preferences.appearance = AppAppearance.dark;
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF000000));
      expect(IosColors.surface, const Color(0xFF1C1C1E));
      expect(IosColors.label, const Color(0xFFF5F5F7));
      expect(IosColors.userBubble, isNot(IosColors.blue));
      expect(IosColors.userBubbleText, IosColors.label);
      expect(find.text('换肤'), findsOneWidget);
    } finally {
      preferences.appearance = previous;
    }
  });

  testWidgets('top model title opens the selector and handles long IDs', (
    tester,
  ) async {
    var taps = 0;
    const label = '聚合平台 · provider/very-long-model-id-with-suffix';
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 600,
            child: Scaffold(
              appBar: iosAppBar(
                title: label,
                titleWidget: ChatModelTitle(
                  label: label,
                  providerName: 'OpenAI',
                  providerPresetId: 'openai',
                  onPressed: () => taps++,
                ),
                actions: [
                  const Padding(padding: EdgeInsets.all(14), child: Text('更多')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(label));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('top title has no model switch before setup', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatModelTitle(label: '模型之间', onPressed: null)),
      ),
    );
    expect(find.text('模型之间'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_down), findsNothing);
  });

  testWidgets('chat actions stay in More and dispatch correctly', (
    tester,
  ) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ChatMoreButton(
                onNewTopic: () => selected.add('new'),
                onModel: () => selected.add('model'),
                onProviders: () => selected.add('providers'),
                canChangeModel: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('对话列表'), findsNothing);
    expect(find.text('新对话'), findsNothing);
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);
    for (final (label, expected) in [
      ('新对话', 'new'),
      ('切换模型', 'model'),
      ('模型服务', 'providers'),
    ]) {
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(selected.last, expected);
    }
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(selected.length, 3);
  });

  testWidgets('More omits model switch before a service is configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMoreButton(
            onNewTopic: () {},
            onModel: () {},
            onProviders: () {},
            canChangeModel: false,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    expect(find.text('切换模型'), findsNothing);
    expect(find.text('模型服务'), findsOneWidget);
  });

  test('loading duration shows milliseconds and seconds plus milliseconds', () {
    expect(formatLoadingDuration(56), '56ms');
    expect(formatLoadingDuration(999), '999ms');
    expect(formatLoadingDuration(1000), '1s 000ms');
    expect(formatLoadingDuration(12345), '12s 345ms');
  });

  testWidgets(
    'loading indicator updates elapsed time without rebuilding chat',
    (tester) async {
      final elapsed = ValueNotifier<int>(42);
      addTearDown(elapsed.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatLoadingStatus(elapsedMilliseconds: elapsed)),
        ),
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('加载中 · 42ms'), findsOneWidget);
      elapsed.value = 1234;
      await tester.pump();
      expect(find.text('加载中 · 1s 234ms'), findsOneWidget);
    },
  );

  test('large prefixed model lists group; short lists stay flat', () {
    final models = [
      for (var i = 0; i < 12; i++) 'openai/gpt-$i',
      for (var i = 0; i < 10; i++) 'anthropic/claude-$i',
      'local-model',
    ];
    final groups = groupModelsByPrefix(models);
    expect(groups?.map((group) => group.prefix), [
      'anthropic',
      'openai',
      '其他模型',
    ]);
    expect(groups?[1].models.length, 12);
    expect(groupModelsByPrefix(models.take(6).toList()), isNull);
    expect(
      groupModelsByPrefix([
        for (var i = 0; i < 10; i++) 'deepseek-ai/model-$i',
        for (var i = 0; i < 10; i++) '~openai/model-$i',
      ])?.map((group) => group.prefix),
      ['deepseek-ai', '~openai'],
    );
    expect(
      groupModelsByPrefix([for (var i = 0; i < 21; i++) 'model-$i']),
      isNull,
    );
  });

  test('hyphenated model families group in a large aggregator catalog', () {
    final models = [
      'LongCat-2.0',
      'MiniMax-M2.7',
      'MiniMax-M2.7-highspeed',
      'MiniMax-M3',
      'MiniMax-M3-highspeed',
      for (var i = 0; i < 18; i++) 'claude-opus-4-$i',
      for (var i = 0; i < 50; i++) 'other_$i',
    ];
    final groups = groupModelsByPrefix(models)!;
    expect(groups.map((group) => group.prefix), ['claude', 'MiniMax', '其他模型']);
    expect(groups[0].models, contains('claude-opus-4-17'));
    expect(groups[1].models, contains('MiniMax-M3-highspeed'));
    expect(groups[2].models, contains('LongCat-2.0'));
  });

  testWidgets('hyphenated server models expand and keep full IDs selectable', (
    tester,
  ) async {
    final models = [
      'LongCat-2.0',
      for (var i = 0; i < 4; i++) 'MiniMax-M$i',
      for (var i = 0; i < 20; i++) 'claude-opus-4-$i',
      for (var i = 0; i < 50; i++) 'independent_$i',
    ];
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ModelCatalog(
                models: models,
                query: '',
                onSelected: (id) => chosen = id,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('MiniMax'), findsOneWidget);
    expect(find.text('claude-opus-4-19'), findsNothing);
    await tester.tap(find.text('claude'));
    await tester.pump();
    await tester.tap(find.text('claude-opus-4-0'));
    expect(chosen, 'claude-opus-4-0');
  });

  testWidgets('large model picker expands a prefix and searches all IDs', (
    tester,
  ) async {
    final models = [
      for (var i = 0; i < 12; i++) 'openai/gpt-$i',
      for (var i = 0; i < 10; i++) 'anthropic/claude-$i',
    ];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              selected = await Navigator.push<String>(
                context,
                CupertinoPageRoute(builder: (_) => ModelPicker(models: models)),
              );
            },
            child: const Text('选择'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    expect(find.text('openai'), findsOneWidget);
    expect(find.text('openai/gpt-11'), findsNothing);
    await tester.tap(find.text('openai'));
    await tester.pumpAndSettle();
    expect(find.text('openai/gpt-11'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'claude-9');
    await tester.pumpAndSettle();
    expect(find.text('anthropic/claude-9'), findsOneWidget);
    await tester.tap(find.text('anthropic/claude-9'));
    await tester.pumpAndSettle();
    expect(selected, 'anthropic/claude-9');
  });

  testWidgets('privacy screen requires confirmation before clearing data', (
    tester,
  ) async {
    var clearCount = 0;
    await tester.pumpWidget(
      MaterialApp(home: PrivacyScreen(clearData: () async => clearCount++)),
    );
    expect(find.textContaining('数据库内容未加密'), findsOneWidget);
    await tester.ensureVisible(find.text('清空所有本地数据'));
    await tester.tap(find.text('清空所有本地数据'));
    await tester.pumpAndSettle();
    expect(clearCount, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(clearCount, 0);
    await tester.tap(find.text('清空所有本地数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(clearCount, 1);
  });

  testWidgets('privacy screen blocks clearing while a reply is generating', (
    tester,
  ) async {
    var clearCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyScreen(
          clearData: () async => clearCount++,
          canClearData: () => false,
        ),
      ),
    );
    await tester.ensureVisible(find.text('清空所有本地数据'));
    await tester.tap(find.text('清空所有本地数据'));
    await tester.pumpAndSettle();
    expect(clearCount, 0);
    expect(find.textContaining('请先停止回复或等待标题生成完成'), findsOneWidget);
  });

  testWidgets('empty custom provider can switch directly to JSON import', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProviderEditor()));

    expect(find.byType(CupertinoSlidingSegmentedControl<bool>), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsWidgets);
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();

    final jsonField = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).first,
    );
    expect(jsonField.controller?.text, contains('"protocol": "openai_chat"'));
    expect(find.text('完整配置 JSON'), findsOneWidget);
  });

  testWidgets('all provider logos render from bundled assets', (tester) async {
    for (final preset in providerPresets) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SvgPicture.asset(preset.iconAsset))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: preset.id);
    }
  });

  testWidgets('server model picker filters IDs and returns selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            child: const Text('选择'),
            onPressed: () async {
              selected = await Navigator.push<String>(
                context,
                CupertinoPageRoute(
                  builder: (_) =>
                      const ModelPicker(models: ['alpha-model', 'beta-model']),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoSearchTextField), 'beta');
    await tester.pumpAndSettle();
    expect(find.text('alpha-model'), findsNothing);
    await tester.tap(find.text('beta-model'));
    await tester.pumpAndSettle();
    expect(selected, 'beta-model');
  });

  testWidgets(
    'model picker keeps cached IDs after failed refresh and replaces on success',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ModelPicker(
            models: const ['cached-model'],
            fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
            onRefresh: () async {
              attempts++;
              if (attempts == 1) throw const ApiException('网络失败');
              return ['fresh-model'];
            },
          ),
        ),
      );
      expect(find.text('cached-model'), findsOneWidget);
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('cached-model'), findsOneWidget);
      expect(find.textContaining('刷新失败'), findsOneWidget);
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('fresh-model'), findsOneWidget);
      expect(find.text('cached-model'), findsNothing);
    },
  );

  testWidgets('chat selector shows cached models before refreshing', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatModelSelector(
          providers: const [
            ProviderConfig(
              id: 3,
              name: '聚合服务',
              baseUrl: 'https://example.com/v1',
              model: 'default',
              protocol: ApiProtocol.openAi,
            ),
          ],
          topics: const [],
          providerId: 3,
          model: 'default',
          loadCachedModels: (_) async => CachedModelList(
            baseUrl: 'https://example.com/v1',
            protocol: ApiProtocol.openAi,
            models: const ['cached-model'],
            fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          ),
          loadModels: (_) async {
            requests++;
            if (requests == 1) throw const ApiException('网络失败');
            return ['fresh-model'];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('cached-model'), findsOneWidget);
    expect(requests, 0);
    await tester.ensureVisible(find.text('刷新模型列表'));
    await tester.tap(find.text('刷新模型列表'));
    await tester.pumpAndSettle();
    expect(find.text('cached-model'), findsOneWidget);
    expect(find.textContaining('已保留缓存'), findsOneWidget);
    await tester.tap(find.text('刷新模型列表'));
    await tester.pumpAndSettle();
    expect(find.text('fresh-model'), findsOneWidget);
    expect(find.text('cached-model'), findsNothing);
  });

  testWidgets('late cache read cannot replace a refreshed model list', (
    tester,
  ) async {
    final delayedCache = Completer<CachedModelList?>();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatModelSelector(
          providers: const [
            ProviderConfig(
              id: 3,
              name: '聚合服务',
              baseUrl: 'https://example.com/v1',
              model: 'default',
              protocol: ApiProtocol.openAi,
            ),
          ],
          topics: const [],
          providerId: 3,
          model: 'default',
          loadCachedModels: (_) => delayedCache.future,
          loadModels: (_) async => ['fresh-model'],
        ),
      ),
    );
    await tester.ensureVisible(find.text('从服务端获取模型列表'));
    await tester.tap(find.text('从服务端获取模型列表'));
    await tester.pumpAndSettle();
    expect(find.text('fresh-model'), findsOneWidget);
    delayedCache.complete(
      CachedModelList(
        baseUrl: 'https://example.com/v1',
        protocol: ApiProtocol.openAi,
        models: const ['stale-model'],
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fresh-model'), findsOneWidget);
    expect(find.text('stale-model'), findsNothing);
  });

  testWidgets('chat model selector chooses a service model on one page', (
    tester,
  ) async {
    const providers = [
      ProviderConfig(
        id: 1,
        name: '服务 A',
        baseUrl: 'https://a.example.com/v1',
        model: 'model-a',
        protocol: ApiProtocol.openAi,
      ),
      ProviderConfig(
        id: 2,
        name: '服务 B',
        baseUrl: 'https://b.example.com/v1',
        model: 'model-b',
        protocol: ApiProtocol.openAi,
      ),
    ];
    ChatModelSelection? selected;
    int? fetchedProviderId;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              selected = await Navigator.push<ChatModelSelection>(
                context,
                CupertinoPageRoute(
                  builder: (_) => ChatModelSelector(
                    providers: providers,
                    topics: const [],
                    providerId: 1,
                    model: 'model-a',
                    loadModels: (provider) async {
                      fetchedProviderId = provider.id;
                      return ['model-b-1', 'model-b-2'];
                    },
                  ),
                ),
              );
            },
            child: const Text('打开切换页'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开切换页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('服务 B'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('从服务端获取模型列表'));
    await tester.tap(find.text('从服务端获取模型列表'));
    await tester.pumpAndSettle();
    expect(fetchedProviderId, 2);
    await tester.enterText(find.byType(CupertinoSearchTextField), 'b-2');
    await tester.pumpAndSettle();
    expect(find.text('model-b-1'), findsNothing);
    await tester.ensureVisible(find.text('model-b-2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('model-b-2'));
    await tester.pumpAndSettle();
    expect(selected?.providerId, 2);
    expect(selected?.model, 'model-b-2');
  });

  testWidgets('chat selector groups large server model lists', (tester) async {
    ChatModelSelection? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              selected = await Navigator.push<ChatModelSelection>(
                context,
                CupertinoPageRoute(
                  builder: (_) => ChatModelSelector(
                    providers: const [
                      ProviderConfig(
                        id: 1,
                        name: '聚合服务',
                        baseUrl: 'https://example.com/v1',
                        model: 'openai/gpt-0',
                        protocol: ApiProtocol.openAi,
                      ),
                    ],
                    topics: const [],
                    providerId: 1,
                    model: 'openai/gpt-0',
                    loadModels: (_) async => [
                      for (var i = 0; i < 12; i++) 'openai/gpt-$i',
                      for (var i = 0; i < 10; i++) 'anthropic/claude-$i',
                    ],
                  ),
                ),
              );
            },
            child: const Text('打开切换页'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开切换页'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('从服务端获取模型列表'));
    await tester.tap(find.text('从服务端获取模型列表'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('anthropic'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('anthropic'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('anthropic/claude-9'),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('anthropic/claude-9'));
    await tester.pumpAndSettle();
    expect(selected?.model, 'anthropic/claude-9');
  });

  testWidgets('manual model ID remains available after list request fails', (
    tester,
  ) async {
    ChatModelSelection? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () async {
              selected = await Navigator.push<ChatModelSelection>(
                context,
                CupertinoPageRoute(
                  builder: (_) => ChatModelSelector(
                    providers: const [
                      ProviderConfig(
                        id: 7,
                        name: '自定义服务',
                        baseUrl: 'https://example.com/v1',
                        model: 'default',
                        protocol: ApiProtocol.openAi,
                      ),
                    ],
                    topics: const [],
                    providerId: 7,
                    model: 'default',
                    loadModels: (_) async =>
                        throw const ApiException('接口不支持模型列表'),
                  ),
                ),
              );
            },
            child: const Text('打开切换页'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开切换页'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('从服务端获取模型列表'));
    await tester.tap(find.text('从服务端获取模型列表'));
    await tester.pumpAndSettle();
    expect(find.textContaining('仍可手动输入模型 ID'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField).first, 'custom-id');
    await tester.ensureVisible(find.text('使用此模型'));
    await tester.tap(find.text('使用此模型'));
    await tester.pumpAndSettle();
    expect(selected?.model, 'custom-id');
  });
}
