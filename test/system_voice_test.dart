import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/voice/system_voice.dart';
import 'package:mulit_ai_flutter/voice/voice_client.dart';
import 'package:mulit_ai_flutter/voice/voice_selection.dart';
import 'package:mulit_ai_flutter/watch/watch_chat.dart';
import 'package:mulit_ai_flutter/voice/voice_settings_screen.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

import 'sqflite_stub.dart';

class _Store extends Fake implements ChatStore {
  final values = <String, String>{};
  final voices = <VoiceProviderConfig>[];
  @override
  Future<String?> setting(String key) async => values[key];
  @override
  Future<void> saveSetting(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<List<VoiceProviderConfig>> voiceProviders() async => voices;
  @override
  Future<List<ProviderConfig>> providers() async => [];
  @override
  Future<SearchProviderConfig?> selectedSearchProvider() async => null;
}

const cloud = VoiceProviderConfig(
  id: 'cloud',
  name: 'Cloud',
  protocol: VoiceProtocol.openAi,
  baseUrl: 'https://example.com',
  asrModel: 'asr',
  ttsModel: 'tts',
  voice: 'voice',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useSqflitePluginFactory);
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVoice.channel, null);
  });

  test('fresh iPhone selects system voice but requires opting in to phone/watch playback', () async {
    final store = _Store();
    await initializeSystemVoiceDefaults(store);
    expect(store.values, {
      'voice_asr_id': systemVoiceId,
      'voice_tts_id': systemVoiceId,
      'voice_auto_read': '0',
      'watch_tts_enabled': '0',
    });
    store.values['voice_auto_read'] = '1';
    store.values['watch_tts_enabled'] = '1';
    store.values['voice_asr_id'] = '';
    await initializeSystemVoiceDefaults(store);
    expect(await selectedVoiceId(store, 'voice_asr_id'), '');
    expect(store.values['voice_auto_read'], '1');
    expect(store.values['watch_tts_enabled'], '1');
  });

  test('existing custom services and selected IDs survive system default initialization', () async {
    final store = _Store()..voices.add(cloud);
    expect(await selectedVoiceId(store, 'voice_asr_id'), cloud.id);
    store.values.addAll({'voice_asr_id': cloud.id, 'voice_tts_id': cloud.id});
    await initializeSystemVoiceDefaults(store);
    expect(store.values, {'voice_asr_id': cloud.id, 'voice_tts_id': cloud.id});
    store.values['voice_asr_id'] = systemVoiceId;
    expect(await usesSystemVoice(store, 'voice_asr_id'), true);
    expect(await usesSystemVoice(store, 'voice_tts_id'), false);
  });

  test(
    'Android retains cloud defaults and cannot select Apple system speech',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final store = _Store();
      await initializeSystemVoiceDefaults(store);
      expect(store.values, isEmpty);
      expect(await selectedVoiceId(store, 'voice_asr_id'), isNull);
      store.values['voice_asr_id'] = systemVoiceId;
      expect(await usesSystemVoice(store, 'voice_asr_id'), false);
    },
  );

  test('system Watch snapshot needs no ASR/TTS credentials and keeps legacy cloud readiness false', () async {
    final store = _Store();
    await initializeSystemVoiceDefaults(store);
    final config = await WatchChatProcessor(store: store).configuration();
    expect(config['systemAsr'], true);
    expect(config['systemTts'], true);
    expect(config['asrReady'], false);
    expect(config['asr'], isNull);
    expect(config['tts'], isNull);
    store.values[systemSpeechVoiceSetting] = 'system-test-voice';
    expect(
      (await WatchChatProcessor(store: store)
          .configuration())['systemVoiceIdentifier'],
      'system-test-voice',
    );
    expect(config['speak'], false);
    store.values['watch_tts_enabled'] = '1';
    expect(
      (await WatchChatProcessor(store: store).configuration())['speak'],
      true,
    );
  });

  test('native system transcription validates returned text and passes audio without credentials', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVoice.channel, (call) async {
          calls.add(call);
          return call.method == 'transcribe' ? '  hello\u0000  ' : null;
        });
    await SystemVoice.prepareRecognition('en-US');
    expect(
      await SystemVoice.transcribe(Uint8List.fromList([1, 2]), 'en-US'),
      'hello',
    );
    await SystemVoice.speak('answer', 'en-US', voiceIdentifier: 'voice-test');
    await SystemVoice.stop();
    expect((calls[2].arguments as Map)['voiceIdentifier'], 'voice-test');
    expect(calls.map((call) => call.method), [
      'prepareRecognition',
      'transcribe',
      'speak',
      'stop',
    ]);
    expect(
      (calls[1].arguments as Map).keys,
      unorderedEquals(['audio', 'locale']),
    );
  });

  test(
    'system failures show localized safe messages without native error text',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemVoice.channel, (_) async {
            throw PlatformException(
              code: 'speech_permission',
              message: 'sensitive-native-details',
            );
          });
      await expectLater(
        SystemVoice.prepareRecognition('zh-CN'),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.message,
            'safe message',
            allOf(
              isNot(contains('sensitive-native-details')),
              isNot(startsWith('i18n.')),
            ),
          ),
        ),
      );
    },
  );

  testWidgets(
    'iPhone settings show system sources and retain custom service entry',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemVoice.channel, (call) async => [
          {'identifier': 'voice-test', 'name': 'Test voice', 'language': 'zh-CN', 'quality': 2},
        ]);
      installEmptyDatabaseStub(
        settings: {
          'voice_asr_id': systemVoiceId,
          'voice_tts_id': systemVoiceId,
        },
      );
      await tester.pumpWidget(const MaterialApp(home: VoiceSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text(T('i18n.apple_system_voice')), findsNWidgets(2));
      expect(find.text(T('i18n.add_voice_provider')), findsOneWidget);
      expect(find.text(T('i18n.system_speech_voice')), findsOneWidget);
      await tester.tap(find.text(T('i18n.system_speech_voice')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Test voice'), findsOneWidget);
      await tester.tap(find.textContaining('Test voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(T('i18n.transcription_service')));
      await tester.pumpAndSettle();
      expect(find.text(T('i18n.apple_system_voice')), findsNWidgets(3));
      expect(find.text(T('i18n.none')), findsOneWidget);
      await tester.tap(find.text(T('i18n.cancel')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(T('i18n.watch_system_dictation_recommendation')), 200);
      expect(find.text(T('i18n.watch_system_dictation_recommendation')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'system voice catalog preserves native identifiers and voice quality',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemVoice.channel,
            (call) async => [
              {
                'identifier': 'voice-test',
                'name': 'Test voice',
                'language': 'zh-CN',
                'quality': 2,
              },
            ],
          );
      final voices = await SystemVoice.availableVoices();
      expect(voices.single.identifier, 'voice-test');
      expect(voices.single.language, 'zh-CN');
      expect(voices.single.quality, 2);
      expect(voices.single.label, contains('Test voice'));
    },
  );
}
