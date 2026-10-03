import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/watch_chat.dart';

class _Store extends Fake implements ChatStore {
  final values = <String, String>{};
  final services = <ProviderConfig>[];
  final voices = <VoiceProviderConfig>[];
  final textKeys = <int, String?>{};
  String? voiceKey = 'test-key';

  @override
  Future<String?> setting(String key) async => values[key];

  @override
  Future<List<ProviderConfig>> providers() async => services;

  @override
  Future<List<VoiceProviderConfig>> voiceProviders() async => voices;

  @override
  Future<String?> voiceApiKey(VoiceProviderConfig service) async =>
      service.textProviderId == null
      ? voiceKey
      : apiKey(service.textProviderId!);

  @override
  Future<String?> apiKey(int id) async =>
      textKeys.containsKey(id) ? textKeys[id] : 'test-key';

  @override
  Future<String> systemPrompt(int providerId, String model) async => '';
}

class _Processor extends WatchChatProcessor {
  _Processor(ChatStore store) : super(store: store);
  String? sent;
  bool? requestedSpeech;

  @override
  Future<void> sendTranscript(
    String text, {
    bool? speak,
    required WatchUpdate onUpdate,
  }) async {
    sent = text;
    requestedSpeech = speak;
    await onUpdate({'stage': 'complete', 'answer': 'reply'});
  }
}

_Store _configuredStore([String voiceUrl = 'https://example.com']) {
  final store = _Store();
  store.services.add(
    const ProviderConfig(
      id: 1,
      name: 'Text',
      baseUrl: 'https://example.com',
      model: 'chat',
      protocol: ApiProtocol.openAi,
    ),
  );
  store.voices.add(
    VoiceProviderConfig(
      id: 'asr',
      name: 'Voice',
      protocol: VoiceProtocol.openAi,
      baseUrl: voiceUrl,
      asrModel: 'asr',
      ttsModel: 'tts',
      voice: 'voice',
    ),
  );
  store.values['voice_asr_id'] = 'asr';
  return store;
}

void main() {
  test(
    'sync uses the phone model instead of stale legacy watch settings',
    () async {
      final store = _configuredStore();
      store.services.add(
        const ProviderConfig(
          id: 2,
          name: 'DeepSeek',
          baseUrl: 'https://example.org',
          model: 'default-model',
          protocol: ApiProtocol.openAi,
        ),
      );
      store.values.addAll({
        'watch_provider_id': '1',
        'watch_model_id': 'old-model',
        'last_chat_selection': const ChatSelection(
          2,
          'deepseek-flash',
        ).toJson(),
      });
      final processor = WatchChatProcessor(store: store);
      final preferences = await processor.preferences();
      expect(preferences['providerName'], 'DeepSeek');
      expect(preferences['model'], 'deepseek-flash');
      expect(preferences.keys, isNot(contains('apiKey')));
      final config = await processor.configuration();
      expect(config['providerId'], 2);
      expect(config['model'], 'deepseek-flash');
      expect(config['baseUrl'], 'https://example.org');

      store.values['watch_chat_selection'] = const ChatSelection(
        2,
        'custom/model-id',
      ).toJson();
      expect((await processor.preferences())['model'], 'custom/model-id');
      store.values['watch_chat_selection'] = const ChatSelection(
        1,
        'another-model',
      ).toJson();
      expect((await processor.configuration())['providerId'], 1);
      expect((await processor.preferences())['model'], 'another-model');
    },
  );

  test('Apple Watch metadata checks readiness without sending keys', () async {
    final store = _Store();
    store.services.addAll([
      const ProviderConfig(
        id: 1,
        name: 'First',
        baseUrl: 'https://example.com',
        model: 'default-1',
        protocol: ApiProtocol.openAi,
      ),
      const ProviderConfig(
        id: 2,
        name: 'Chosen',
        baseUrl: 'https://example.com',
        model: 'default-2',
        protocol: ApiProtocol.openAi,
      ),
    ]);
    store.values.addAll({
      'watch_provider_id': '2',
      'watch_model_id': 'manual-model',
      'voice_auto_send': '0',
      'watch_tts_enabled': '1',
    });
    expect(await WatchChatProcessor(store: store).preferences(), {
      'providerName': 'Chosen',
      'model': 'manual-model',
      'autoSend': false,
      'speak': true,
      'textReady': true,
      'asrReady': false,
    });
  });

  test(
    'deleted service falls back without retaining its manual model',
    () async {
      final store = _Store();
      store.services.add(
        const ProviderConfig(
          id: 1,
          name: 'Available',
          baseUrl: 'https://example.com',
          model: 'default',
          protocol: ApiProtocol.openAi,
        ),
      );
      store.values.addAll({
        'watch_provider_id': '99',
        'watch_model_id': 'deleted-model',
      });
      expect(await WatchChatProcessor(store: store).preferences(), {
        'providerName': 'Available',
        'model': 'default',
        'autoSend': true,
        'speak': false,
        'textReady': true,
        'asrReady': false,
      });
    },
  );

  test('empty configuration still syncs usable display defaults', () async {
    expect(await WatchChatProcessor(store: _Store()).preferences(), {
      'providerName': '',
      'model': '',
      'autoSend': true,
      'speak': false,
      'textReady': false,
      'asrReady': false,
    });
  });
  test(
    'readiness requires both selected services and usable credentials',
    () async {
      for (final (text, voice) in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ]) {
        final store = _configuredStore();
        if (!text) store.services.clear();
        if (!voice) store.voices.clear();
        final prefs = await WatchChatProcessor(store: store).preferences();
        expect(prefs['textReady'], text);
        expect(prefs['asrReady'], voice);
        expect(prefs.keys, isNot(contains('apiKey')));
        expect(prefs.keys, isNot(contains('asr')));
      }
      final store = _configuredStore();
      store.textKeys[1] = '  ';
      store.voiceKey = null;
      final prefs = await WatchChatProcessor(store: store).preferences();
      expect(prefs['textReady'], false);
      expect(prefs['asrReady'], false);
    },
  );

  test('ASR selection, model and reused text key must be configured', () async {
    final store = _configuredStore();
    store.values['voice_asr_id'] = 'deleted';
    expect(
      (await WatchChatProcessor(store: store).preferences())['asrReady'],
      false,
    );
    store.values['voice_asr_id'] = 'asr';
    store.voices[0] = const VoiceProviderConfig(
      id: 'asr',
      name: 'Voice',
      protocol: VoiceProtocol.openAi,
      baseUrl: 'https://example.com',
      asrModel: '',
      ttsModel: 'tts',
      voice: 'voice',
    );
    expect(
      (await WatchChatProcessor(store: store).preferences())['asrReady'],
      false,
    );
    store.voices[0] = const VoiceProviderConfig(
      id: 'asr',
      name: 'Voice',
      protocol: VoiceProtocol.openAi,
      baseUrl: 'https://example.com',
      asrModel: 'asr',
      ttsModel: 'tts',
      voice: 'voice',
      textProviderId: 1,
    );
    store.textKeys[1] = null;
    expect(
      (await WatchChatProcessor(store: store).preferences())['asrReady'],
      false,
    );
  });

  test(
    'missing text service blocks recognition even with working ASR',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.write('{"text":"recognized"}');
        await request.response.close();
      });
      try {
        final store = _configuredStore('http://127.0.0.1:${server.port}');
        store.services.clear();
        final processor = WatchChatProcessor(store: store);
        await expectLater(
          processor.process(Uint8List.fromList([1]), onUpdate: (_) async {}),
          throwsA(isA<WatchChatException>()),
        );
        await expectLater(
          processor.remoteTranscribe(Uint8List.fromList([1])),
          throwsA(isA<WatchChatException>()),
        );
        expect(requests, 0);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'missing setup snapshot invalidates a previously usable Wear configuration',
    () async {
      final store = _configuredStore();
      final processor = WatchChatProcessor(store: store);
      final ready = await processor.configuration();
      expect(ready['textReady'], true);
      expect(ready['asrReady'], true);
      store.services.clear();
      store.voices.clear();
      final invalid = await processor.configuration();
      expect(invalid['version'], 1);
      expect(invalid['textReady'], false);
      expect(invalid['asrReady'], false);
      expect(invalid['apiKey'], isNull);
      expect(invalid['asr'], isNull);
    },
  );

  test(
    'watch auto-send override works without changing phone defaults',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'text': 'recognized'}));
        await request.response.close();
      });
      try {
        for (final (phoneSetting, override, sends) in [
          ('1', false, false),
          ('0', true, true),
          ('0', null, false),
          ('1', null, true),
        ]) {
          final store = _configuredStore('http://127.0.0.1:${server.port}');
          store.values.addAll({
            'voice_auto_send': phoneSetting,
            'voice_asr_id': 'asr',
          });
          store.voices.clear();
          store.voices.add(
            VoiceProviderConfig(
              id: 'asr',
              name: 'Local mock',
              protocol: VoiceProtocol.openAi,
              baseUrl: 'http://127.0.0.1:${server.port}',
              asrModel: 'asr',
              ttsModel: 'tts',
              voice: 'voice',
            ),
          );
          final processor = _Processor(store);
          final updates = <Map<String, Object?>>[];
          await processor.process(
            Uint8List.fromList([1, 2, 3]),
            autoSend: override,
            speak: true,
            onUpdate: (update) async {
              updates.add(update);
            },
          );
          expect(processor.sent, sends ? 'recognized' : null);
          expect(
            updates.last['stage'],
            sends ? 'complete' : 'awaiting_confirmation',
          );
          if (sends) expect(processor.requestedSpeech, true);
          expect(store.values['voice_auto_send'], phoneSetting);
        }
      } finally {
        await server.close(force: true);
      }
    },
  );
}
