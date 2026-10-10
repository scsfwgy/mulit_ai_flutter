import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/voice/voice_recording.dart';
import 'package:mulit_ai_flutter/watch/watch_chat.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

class _Store extends Fake implements ChatStore {
  final values = <String, String>{};
  final services = <ProviderConfig>[];
  final voices = <VoiceProviderConfig>[];
  final searches = <SearchProviderConfig>[];
  final searchKeys = <String, String>{};

  @override
  Future<List<SearchProviderConfig>> searchProviders() async => searches;

  @override
  Future<SearchProviderConfig?> selectedSearchProvider() async =>
      searches.where((s) => s.id == values['search_provider_id']).firstOrNull;

  @override
  Future<String?> searchApiKey(String id) async => searchKeys[id];
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
  test('Apple full snapshot contains only selected credentials and invalidates deleted services', () async {
    final store = _configuredStore();
    store.values['voice_tts_id'] = 'asr';
    final processor = WatchChatProcessor(store: store);
    final config = await processor.configuration();
    expect(config['protocol'], 'openai_chat');
    expect(config['apiKey'], 'test-key');
    expect((config['asr'] as Map)['apiKey'], 'test-key');
    expect((config['asr'] as Map)['providerName'], 'Voice');
    expect((config['asr'] as Map)['asrModel'], 'asr');
    expect((config['tts'] as Map)['providerName'], 'Voice');
    expect((config['tts'] as Map)['ttsModel'], 'tts');
    expect((config['tts'] as Map)['voice'], 'voice');
    expect(
      jsonEncode(await processor.preferences()),
      isNot(contains('test-key')),
    );
    store.textKeys[1] = null;
    store.voiceKey = null;
    final revoked = await processor.configuration();
    expect(revoked['textReady'], false);
    expect(revoked['asrReady'], false);
    expect(revoked['apiKey'], isNull);
    expect(revoked['asr'], isNull);
  });

  test('search snapshot carries selected key, follows phone toggle and revokes deleted service', () async {
    final store = _configuredStore();
    const search = SearchProviderConfig(
      id: 'search',
      name: 'My Tavily',
      service: SearchService.tavily,
      endpoint: 'https://api.tavily.com/search',
      maxResults: 3,
      detailed: true,
      timeRange: SearchTimeRange.week,
    );
    store.searches.add(search);
    store.searchKeys[search.id] = 'test-search-key';
    store.values.addAll({
      'search_enabled': '1',
      'search_provider_id': search.id,
    });
    final processor = WatchChatProcessor(store: store);
    final snapshot = await processor.configuration();
    expect(snapshot['searchEnabled'], true);
    expect(snapshot['searchReady'], true);
    expect((snapshot['search'] as Map)['apiKey'], 'test-search-key');
    expect((snapshot['search'] as Map)['maxResults'], 3);
    final display = await processor.preferences();
    expect(display['searchProviderName'], 'My Tavily');
    expect(display['searchService'], 'tavily');
    expect(jsonEncode(display), isNot(contains('test-search-key')));
    store.values['search_enabled'] = '0';
    expect((await processor.configuration())['searchEnabled'], false);
    store.searches.clear();
    final revoked = await processor.configuration();
    expect(revoked['search'], isNull);
    expect(revoked['searchReady'], false);
  });

  test('watch phone route searches once before both model protocols and stops on search errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var searches = 0, models = 0, fail = false;
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (request.uri.path == '/search') {
        searches++;
        expect(
          request.headers.value('authorization'),
          'Bearer test-search-key',
        );
        expect(body['query'], 'question');
        if (fail) {
          request.response.statusCode = 401;
        } else {
          request.response.write(
            jsonEncode({
              'results': [
                {
                  'title': 'Source',
                  'url': 'https://example.com/source',
                  'content': 'real evidence',
                },
              ],
            }),
          );
        }
      } else {
        models++;
        expect(jsonEncode(body['messages']), contains('real evidence'));
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        if (request.uri.path.endsWith('/messages')) {
          expect(body['system'], contains('web search evidence'));
          request.response.write(
            'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"answer"}}\n\ndata: {"type":"message_stop"}\n\n',
          );
        } else {
          request.response.write(
            'data: {"choices":[{"delta":{"content":"answer"}}]}\n\ndata: [DONE]\n\n',
          );
        }
      }
      await request.response.close();
    });
    try {
      final root = 'http://127.0.0.1:${server.port}';
      final store = _configuredStore();
      store.searches.add(
        SearchProviderConfig(
          id: 'search',
          name: 'Tavily',
          service: SearchService.tavily,
          endpoint: '$root/search',
        ),
      );
      store.searchKeys['search'] = 'test-search-key';
      for (final protocol in ApiProtocol.values) {
        store.services[0] = ProviderConfig(
          id: 1,
          name: 'Test',
          baseUrl: root,
          model: 'chat',
          protocol: protocol,
        );
        final updates = <Map<String, Object?>>[];
        await WatchChatProcessor(store: store).remoteReply(
          '[{"role":"user","content":"question"}]',
          1,
          'chat',
          searchEnabled: true,
          searchProviderId: 'search',
          requireComplete: true,
          onUpdate: (u) async {
            updates.add(u);
          },
        );
        expect(updates.last['stage'], 'complete', reason: jsonEncode(updates));
      }
      expect(searches, 2);
      expect(models, 2);
      fail = true;
      final updates = <Map<String, Object?>>[];
      await WatchChatProcessor(store: store).remoteReply(
        '[{"role":"user","content":"question"}]',
        1,
        'chat',
        searchEnabled: true,
        searchProviderId: 'search',
        onUpdate: (u) async {
          updates.add(u);
        },
      );
      expect(models, 2);
      expect(updates.last['stage'], 'error');
      expect(updates.last['retrySafe'], false);
      expect(jsonEncode(updates), isNot(contains('test-search-key')));
    } finally {
      await server.close(force: true);
    }
  });

  test('ambiguous timeout and transport resets cannot switch watch routes', () {
    expect(watchRetrySafe(TimeoutException('unknown')), false);
    expect(
      watchRetrySafe(const SearchException('timeout', networkFailure: true)),
      false,
    );
    expect(
      watchRetrySafe(
        const SearchException('refused', networkFailure: true, retrySafe: true),
      ),
      true,
    );
    expect(
      watchRetrySafe(
        const SocketException('reset', osError: OSError('reset', 54)),
      ),
      false,
    );
    expect(
      watchRetrySafe(
        const SocketException('refused', osError: OSError('refused', 61)),
      ),
      true,
    );
    expect(
      watchRetrySafe(const ApiException('network', kind: ApiErrorKind.network)),
      false,
    );
  });

  test('phone remote reply rejects incomplete SSE and never falls back after partial text', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
      );
      await request.response.close();
    });
    try {
      final store = _configuredStore();
      store.services[0] = ProviderConfig(
        id: 1,
        name: 'Test',
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'chat',
        protocol: ApiProtocol.openAi,
      );
      final updates = <Map<String, Object?>>[];
      await WatchChatProcessor(store: store).remoteReply(
        '[{"role":"user","content":"q"}]',
        1,
        'chat',
        requireComplete: true,
        onUpdate: (update) async {
          updates.add(update);
        },
      );
      expect(updates.last['stage'], 'error');
      expect(updates.last['retrySafe'], false);
      expect(updates.where((u) => u['stage'] == 'complete'), isEmpty);
      // Fake store implements no database writes: a remote execution must not persist.
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'connection failure before sending body allows one route fallback',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);
      final store = _configuredStore();
      store.services[0] = ProviderConfig(
        id: 1,
        name: 'Test',
        baseUrl: 'http://127.0.0.1:$port',
        model: 'chat',
        protocol: ApiProtocol.openAi,
      );
      final updates = <Map<String, Object?>>[];
      await WatchChatProcessor(store: store).remoteReply(
        '[{"role":"user","content":"q"}]',
        1,
        'chat',
        requireComplete: true,
        onUpdate: (update) async {
          updates.add(update);
        },
      );
      expect(updates.last['stage'], 'error');
      expect(updates.last['retrySafe'], true);
    },
  );

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
      'openAIRestricted': false,
      'providerName': 'Chosen',
      'model': 'manual-model',
      'autoSend': false,
      'speak': true,
      'textReady': true,
      'asrReady': false,
      'searchEnabled': false,
      'searchReady': false,
      'searchProviderName': '',
      'searchService': '',
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
      'openAIRestricted': false,
        'providerName': 'Available',
        'model': 'default',
        'autoSend': true,
        'speak': false,
        'textReady': true,
        'asrReady': false,
        'searchEnabled': false,
        'searchReady': false,
        'searchProviderName': '',
        'searchService': '',
      });
    },
  );

  test('empty configuration still syncs usable display defaults', () async {
    expect(await WatchChatProcessor(store: _Store()).preferences(), {
      'openAIRestricted': false,
      'providerName': '',
      'model': '',
      'autoSend': true,
      'speak': false,
      'textReady': false,
      'asrReady': false,
      'searchEnabled': false,
      'searchReady': false,
      'searchProviderName': '',
      'searchService': '',
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
            pcm16VoiceWav(Uint8List.fromList([1, 2, 3, 4])),
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
