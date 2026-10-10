import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/provider/api_key_help.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/voice/voice_catalog.dart';
import 'package:mulit_ai_flutter/voice/voice_client.dart';
import 'package:mulit_ai_flutter/voice/voice_recording.dart';
import 'package:mulit_ai_flutter/watch/watch_chat.dart';

import 'sqflite_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useSqflitePluginFactory);
  const channel = MethodChannel('between_models/storefront');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? country;
  String? environment;
  var revision = 0;
  var fail = false;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    country = null;
    environment = 'production';
    fail = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (fail) throw PlatformException(code: 'unavailable');
      return {
        'countryCode': country,
        'environment': environment,
        'revision': ++revision,
      };
    });
    await StorefrontPolicy.instance.refresh();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'mainland and unknown block; overseas stores allow; failure closes access',
    () async {
      for (final code in [null, '', 'CN', 'CHN']) {
        country = code;
        await StorefrontPolicy.instance.refresh();
        expect(StorefrontPolicy.instance.restricted, isTrue, reason: '$code');
      }
      for (final code in ['USA', 'HKG', 'TWN', 'MAC', 'JPN']) {
        country = code;
        await StorefrontPolicy.instance.refresh();
        expect(StorefrontPolicy.instance.restricted, isFalse, reason: code);
      }
      fail = true;
      await StorefrontPolicy.instance.refresh();
      expect(StorefrontPolicy.instance.restricted, isTrue);
    },
  );

  test('timeout and missing bridge do not reuse an overseas result', () async {
    const local = MethodChannel('test/storefront-timeout');
    final policy = StorefrontPolicy(
      channel: local,
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(policy.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(local, null));
    messenger.setMockMethodCallHandler(
      local,
      (_) async => {'countryCode': 'USA', 'environment': 'production'},
    );
    await policy.refresh();
    expect(policy.restricted, isFalse);
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(local, (_) => pending.future);
    await policy.refresh();
    expect(policy.restricted, isTrue);
    pending.complete({'countryCode': 'USA', 'environment': 'production'});
    await Future<void>.delayed(Duration.zero);
    expect(policy.restricted, isTrue);
    messenger.setMockMethodCallHandler(local, null);
    await policy.refresh();
    expect(policy.restricted, isTrue);
  });

  test('development, sandbox and missing environment do not confirm an overseas store', () async {
    country = 'USA';
    for (final source in [null, 'unknown', 'development', 'sandbox']) {
      environment = source;
      await StorefrontPolicy.instance.refresh();
      expect(StorefrontPolicy.instance.restricted, isTrue, reason: '$source');
      expect(availableProviderPresets.any((p) => p.id == 'openai'), isFalse);
    }
    environment = 'production';
    await StorefrontPolicy.instance.refresh();
    expect(StorefrontPolicy.instance.restricted, isFalse);
    environment = 'sandbox';
    await StorefrontPolicy.instance.refresh();
    expect(StorefrontPolicy.instance.restricted, isTrue);
  });

  test(
    'updates take effect and older reads cannot reopen a mainland store',
    () async {
      Future<void> update(String? code, int value) async {
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('changed', {
              'countryCode': code,
              'environment': 'production',
              'revision': value,
            }),
          ),
          (_) {},
        );
      }

      await update('USA', ++revision);
      expect(StorefrontPolicy.instance.restricted, isFalse);
      await update('CHN', ++revision);
      expect(StorefrontPolicy.instance.restricted, isTrue);
      await update('USA', revision - 1);
      expect(StorefrontPolicy.instance.restricted, isTrue);
    },
  );

  test('official domains and preset identity are blocked, compatible providers remain usable', () async {
    for (final endpoint in [
      'https://api.openai.com/v1',
      'https://API.OPENAI.COM./v1',
      'https://platform.openai.com/api-keys',
      'https://openai.com',
    ]) {
      expect(StorefrontPolicy.instance.blocks(endpoint), isTrue);
    }
    expect(
      StorefrontPolicy.instance.blocks(
        'http://127.0.0.1/v1',
        presetId: 'openai',
      ),
      isTrue,
    );
    for (final endpoint in [
      'https://api.deepseek.com',
      'https://api.openai.com.example.org/v1',
      'https://api.openai.com@custom.example/v1',
    ]) {
      expect(StorefrontPolicy.instance.blocks(endpoint), isFalse);
    }
    expect(textApiKeyUrlForEndpoint('https://api.openai.com/v1'), isNull);
    expect(availableProviderPresets.any((p) => p.id == 'openai'), isFalse);
    expect(availableProviderPresets.any((p) => p.id == 'deepseek'), isTrue);
    country = 'USA';
    await StorefrontPolicy.instance.refresh();
    expect(availableProviderPresets.any((p) => p.id == 'openai'), isTrue);
  });

  test(
    'chat, titles and models are rejected before sending any HTTP request',
    () async {
      // Restore real loopback HTTP after the widget binding installs its 400 stub.
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previous);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var sent = 0;
      server.listen((request) async {
        sent++;
        request.response.write(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n',
        );
        await request.response.close();
      });
      final provider = ProviderConfig(
        id: 1,
        name: 'renamed',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'test',
        protocol: ApiProtocol.openAi,
        presetId: 'openai',
      );
      for (final code in [null, 'CHN']) {
        country = code;
        await expectLater(
          ModelApiClient(provider, 'fixture').fetchModels(),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          ModelApiClient(
            provider,
            'fixture',
          ).generateTopicTitle('test', 'hello', 'world'),
          throwsA(isA<ApiException>()),
        );
        expect(sent, 0);
      }
      country = 'USA';
      final response = await ModelApiClient(provider, 'fixture').streamReply([
        ChatMessage(
          id: 0,
          topicId: 0,
          role: 'user',
          content: 'hello',
          createdAt: 0,
        ),
      ], 'test').join();
      expect(response, 'ok');
      expect(sent, 1);
      country = 'CHN';
      await expectLater(
        ModelApiClient(provider, 'fixture').fetchModels(),
        throwsA(isA<ApiException>()),
      );
      expect(sent, 1);
    },
  );

  test(
    'voice, catalog and imported configurations cannot bypass the policy',
    () async {
      var sent = 0;
      final httpClient = MockClient((_) async {
        sent++;
        return http.Response('audio', 200);
      });
      final voice = VoiceProviderConfig(
        id: 'test',
        name: 'renamed',
        protocol: VoiceProtocol.openAi,
        baseUrl: 'https://api.openai.com/v1',
        asrModel: 'asr',
        ttsModel: 'tts',
        voice: 'voice',
      );
      await expectLater(
        VoiceClient(voice, 'fixture', client: httpClient).synthesize('hello'),
        throwsA(isA<VoiceException>()),
      );
      await expectLater(
        VoiceCatalogClient(client: httpClient).fetchModels(
          baseUrl: voice.baseUrl,
          apiKey: 'fixture',
          protocol: voice.protocol,
          kind: VoiceCatalogKind.asr,
        ),
        throwsA(isA<StorefrontRestrictedException>()),
      );
      await expectLater(
        VoiceClient(
          voice,
          'fixture',
          client: httpClient,
        ).transcribe(pcm16VoiceWav(Uint8List.fromList([1, 2]))),
        throwsA(isA<VoiceException>()),
      );
      expect(sent, 0);
      final imported = ProviderConfig.fromQrCode(
        '{"name":"renamed","protocol":"openai_chat",'
        '"baseUrl":"https://api.openai.com/v1","model":"test","apiKey":"fixture"}',
      );
      await expectLater(
        ChatStore.instance.saveProvider(imported.config, apiKey: imported.key),
        throwsA(isA<StorefrontRestrictedException>()),
      );
      await expectLater(
        ChatStore.instance.saveVoiceProvider(voice, apiKey: 'fixture'),
        throwsA(isA<StorefrontRestrictedException>()),
      );
      country = 'USA';
      expect(
        await VoiceClient(
          voice,
          'fixture',
          client: httpClient,
        ).synthesize('hello'),
        Uint8List.fromList('audio'.codeUnits),
      );
      expect(sent, 1);
    },
  );

  test(
    'Android and direct macOS distribution retain existing services',
    () async {
      for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(StorefrontPolicy.instance.restricted, isFalse);
        await StorefrontPolicy.instance.requireAllowed(
          'https://api.openai.com/v1',
        );
      }
    },
  );

  test(
    'watch snapshots withhold blocked credentials and restore them overseas',
    () async {
      final store = _OpenAIWatchStore();
      final processor = WatchChatProcessor(store: store);
      for (final code in [null, 'CHN']) {
        country = code;
        final snapshot = await processor.configuration();
        expect(snapshot['openAIRestricted'], isTrue);
        expect(snapshot['textReady'], isFalse);
        expect(snapshot['apiKey'], isNull);
        expect(snapshot['asr'], isNull);
        expect(snapshot['tts'], isNull);
      }
      country = 'USA';
      final snapshot = await processor.configuration();
      expect(snapshot['openAIRestricted'], isFalse);
      expect(snapshot['textReady'], isTrue);
      expect(snapshot['asrReady'], isTrue);
      expect(snapshot['apiKey'], 'fixture');
      expect(snapshot['tts'], isNotNull);
      expect((await store.providers()).single.presetId, 'openai');
    },
  );

  test(
    'explicit OpenAI aggregator models cannot bypass restrictions',
    () async {
      final provider = ProviderConfig(
        id: 1,
        name: 'Aggregator',
        baseUrl: 'http://127.0.0.1:1',
        model: 'deepseek/chat',
        protocol: ApiProtocol.openAi,
      );
      for (final model in ['openai/gpt-test', '~openai/gpt-latest']) {
        expect(
          StorefrontPolicy.instance.blocks(provider.baseUrl, model: model),
          isTrue,
        );
        await expectLater(
          ModelApiClient(provider, 'fixture').streamReply([
            ChatMessage(
              id: 0,
              topicId: 0,
              role: 'user',
              content: 'hello',
              createdAt: 0,
            ),
          ], model).join(),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          ChatStore.instance.saveProvider(
            provider.copyWith(model: model),
            apiKey: 'fixture',
          ),
          throwsA(isA<StorefrontRestrictedException>()),
        );
      }
      expect(
        StorefrontPolicy.instance.blocks(
          provider.baseUrl,
          model: 'deepseek/chat',
        ),
        isFalse,
      );
    },
  );

  test(
    'changing storefront stops an active stream without resubmitting',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previous);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
        return server.close(force: true);
      });
      var sent = 0;
      server.listen((request) async {
        sent++;
        await request.drain<void>();
        request.response.bufferOutput = false;
        request.response.write(
          'data: {"choices":[{"delta":{"content":"first"}}]}\n\n',
        );
        await request.response.flush();
        await finish.future;
        try {
          await request.response.close();
        } catch (_) {}
      });
      country = 'USA';
      final provider = ProviderConfig(
        id: 1,
        name: 'renamed',
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test',
        protocol: ApiProtocol.openAi,
        presetId: 'openai',
      );
      final iterator = StreamIterator(
        ModelApiClient(provider, 'fixture').streamReply([
          ChatMessage(
            id: 0,
            topicId: 0,
            role: 'user',
            content: 'hello',
            createdAt: 0,
          ),
        ], 'test'),
      );
      addTearDown(() async {
        if (!finish.isCompleted) finish.complete();
        await iterator.cancel();
      });
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, 'first');
      country = 'CHN';
      await StorefrontPolicy.instance.refresh();
      await expectLater(
        iterator.moveNext(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.retrySafe,
            'no automatic resend',
            false,
          ),
        ),
      );
      expect(sent, 1);
      if (!finish.isCompleted) finish.complete();
    },
  );

  testWidgets(
    'restricted storefront hides the OpenAI preset and keeps domestic presets',
    (tester) async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      installEmptyDatabaseStub();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: ProviderScreen()));
      await tester.pumpAndSettle();
      expect(find.text('OpenAI'), findsNothing);
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('OpenAI 兼容'), findsNothing);
      expect(find.text('Chat Completions 兼容'), findsWidgets);
      await tester.runAsync(() async {
        country = 'USA';
        await StorefrontPolicy.instance.refresh();
      });
      await tester.pumpAndSettle();
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('OpenAI 兼容'), findsWidgets);
      await tester.runAsync(() async {
        country = 'CHN';
        await StorefrontPolicy.instance.refresh();
      });
      await tester.pumpAndSettle();
      expect(find.text('OpenAI'), findsNothing);
      expect(find.text('OpenAI 兼容'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class _OpenAIWatchStore extends Fake implements ChatStore {
  @override
  Future<List<ProviderConfig>> providers() async => const [
    ProviderConfig(
      id: 1,
      name: 'renamed',
      baseUrl: 'https://api.openai.com/v1',
      model: 'test',
      protocol: ApiProtocol.openAi,
      presetId: 'openai',
    ),
  ];
  @override
  Future<List<VoiceProviderConfig>> voiceProviders() async => const [
    VoiceProviderConfig(
      id: 'voice',
      name: 'renamed',
      baseUrl: 'https://api.openai.com/v1',
      protocol: VoiceProtocol.openAi,
      asrModel: 'asr',
      ttsModel: 'tts',
      voice: 'voice',
    ),
  ];
  @override
  Future<String?> setting(String key) async => {
    'watch_provider_id': '1',
    'watch_model_id': 'test',
    'voice_asr_id': 'voice',
    'voice_tts_id': 'voice',
  }[key];
  @override
  Future<String?> apiKey(int id) async => 'fixture';
  @override
  Future<String?> voiceApiKey(VoiceProviderConfig config) async => 'fixture';
  @override
  Future<SearchProviderConfig?> selectedSearchProvider() async => null;
  @override
  Future<String> systemPrompt(int providerId, String model) async => '';
}
