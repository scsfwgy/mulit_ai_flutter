import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/chat/message_copy.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/voice/voice_client.dart';
import 'package:mulit_ai_flutter/voice/voice_send_preference.dart';

/// Handles configuration delivery and deferred history sync for the watch.
/// Older watch builds can still send audio through the phone worker.
void startWatchWorker() {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('between_models/watch_worker');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'process') throw MissingPluginException();
    final args = Map<String, Object?>.from(call.arguments as Map);
    final requestId = args['id'] as String;
    final kind = args['kind'] as String? ?? 'audio';
    Future<void> publish(Map<String, Object?> update) =>
        channel.invokeMethod<void>('publish', {
          'id': requestId,
          if (kind.startsWith('remote-')) 'remote': true,
          ...update,
        });
    // 手机可能在上次请求之后切换了语言：后台 engine 会被长期复用（iPhone 的
    // AppleWatchBridge 尤其如此），只在启动时读一次语言会让后续回传的错误文案
    // 停留在旧语言。放在 `try` 之前，刷新失败也不会被当成请求错误上报。
    await _refreshLanguage();
    try {
      if ([
            'audio',
            'confirm',
            'remote-asr',
            'remote-chat',
            'remote-tts',
          ].contains(kind) &&
          !await ApplePurchases.instance.refresh()) {
        throw WatchChatException(T('i18n.start_a_trial_or_unlock'));
      }
      final processor = WatchChatProcessor();
      if (kind == 'confirm') {
        await processor.sendTranscript(
          args['transcript'] as String,
          speak: args['speak'] as bool?,
          onUpdate: publish,
        );
      } else if (kind == 'audio') {
        await processor.process(
          args['audio'] as Uint8List,
          autoSend: args['autoSend'] as bool?,
          speak: args['speak'] as bool?,
          onUpdate: publish,
        );
      } else if (kind == 'apple-configuration') {
        final config = await processor.configuration();
        await publish({
          'kind': 'preferences',
          ...await processor.preferences(),
          'configuration': config,
        });
      } else if (kind == 'apple-preferences') {
        await publish({
          'kind': 'preferences',
          ...await processor.preferences(),
        });
      } else if (kind == 'config') {
        final payload = utf8.encode(
          jsonEncode(await processor.configuration()),
        );
        await channel.invokeMethod<void>('sendConfig', {
          'id': requestId,
          'nodeId': args['nodeId'],
          'payload': Uint8List.fromList(payload),
        });
      } else if (kind == 'turn') {
        await processor.syncTurn(args['turn'] as String);
      } else if (kind == 'remote-asr') {
        final transcript = await processor.remoteTranscribe(
          args['audio'] as Uint8List,
        );
        await publish({'stage': 'complete', 'transcript': transcript});
      } else if (kind == 'remote-chat') {
        await processor.remoteReply(
          args['history'] as String,
          args['providerId'] as int,
          args['model'] as String,
          requireComplete: args['requireComplete'] == true,
          searchEnabled: args['searchEnabled'] == true,
          searchProviderId: args['searchProviderId'] as String?,
          onUpdate: publish,
        );
      } else if (kind == 'remote-tts') {
        final result = await processor.remoteSpeak(args['text'] as String);
        await publish({
          'stage': 'complete',
          'audio': result.bytes,
          'audioFormat': result.format,
        });
      } else {
        throw WatchChatException(T('i18n.invalid_watch_request'));
      }
    } catch (error) {
      if (kind == 'config' || kind == 'turn') rethrow;
      final message = switch (error) {
        WatchChatException() => error.message,
        VoiceException() => error.message,
        ApiException() => error.message,
        SearchException() => error.message,
        _ => T('i18n.watch_phone_request_failed'),
      };
      await publish({
        'stage': 'error',
        'error': message,
        'networkFailure': _isNetworkFailure(error),
        'retrySafe': watchRetrySafe(error),
      });
    }
  });
  unawaited(_announceReady(channel));
}

/// 重新读取手机当前的语言偏好并切换文案表。
///
/// 后台 engine 会被长期复用：iPhone 的 `AppleWatchBridge` 启动一次 worker 后
/// 一直用它处理后续请求，Android 侧也可能复用。语言只在启动时读一次是不够的
/// ——先以英文启动、再把手机切成中文，之后的错误文案会一直停留在英文。因此
/// 每次处理请求前刷新一次，两个平台都覆盖。
///
/// 载入失败不抛异常：沿用已载入的文案表，请求继续，至少不会返回裸 key。
Future<void> _refreshLanguage() async {
  try {
    await AppPreferences.instance.loadLocalization();
  } catch (_) {
    // 忽略：保留现有文案表。
  }
}

/// 载入文案后宣告 worker 就绪。
///
/// 后台是原生新建的独立 FlutterEngine，与前台的静态文案表不共享，所以必须
/// 在这里自行读取语言偏好并载入资源，否则回传手表的错误文案会是裸 key
/// （例如 `i18n.invalid_recording_or_recording_exceeds`）。
///
/// 两端原生都只在收到 `ready` 之后才下发请求，因此这里的等待不会丢请求；
/// Android 侧 `ready` 有 20 秒超时，`loadLocalization` 不会抛异常。
Future<void> _announceReady(MethodChannel channel) async {
  await _refreshLanguage();
  await channel.invokeMethod<void>('ready');
}

typedef WatchUpdate = Future<void> Function(Map<String, Object?> update);
bool _isNetworkFailure(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HttpException ||
    error is http.ClientException ||
    (error is SearchException && error.networkFailure) ||
    (error is ApiException && error.kind == ApiErrorKind.network);

/// A refused connection or DNS lookup failed before a request reached a service.
/// Socket timeouts, resets and generic HTTP client errors are ambiguous.
bool watchRetrySafe(Object error) =>
    (error is ApiException && error.retrySafe) ||
    (error is SearchException && error.retrySafe) ||
    (error is SocketException && [8, 61].contains(error.osError?.errorCode));

typedef WatchAudio = ({Uint8List bytes, String format});

class WatchChatProcessor {
  WatchChatProcessor({ChatStore? store}) : store = store ?? ChatStore.instance;

  final ChatStore store;

  /// Phone network execution for a watch-owned turn. These methods never write
  /// the conversation; the watch stores one result and syncs it afterward.
  Future<String> remoteTranscribe(Uint8List audio) async {
    if (audio.isEmpty || audio.length > 4 * 1024 * 1024) {
      throw WatchChatException(T('i18n.invalid_recording_or_recording_exceeds'));
    }
    await _requireRecordingSetup();
    final asr = await _selectedVoice('voice_asr_id');
    if (asr == null) throw WatchChatException(T('i18n.configure_transcription_on_your_phone'));
    final key = await store.voiceApiKey(asr);
    if (key == null || key.isEmpty) {
      throw WatchChatException(T('i18n.no_transcription_key_configured'));
    }
    final client = VoiceClient(asr, key);
    try {
      return await client.transcribe(audio);
    } finally {
      client.close();
    }
  }

  Future<void> remoteReply(
    String rawHistory,
    int providerId,
    String model, {
    bool requireComplete = false,
    bool searchEnabled = false,
    String? searchProviderId,
    required WatchUpdate onUpdate,
  }) async {
    final source = jsonDecode(rawHistory);
    if (source is! List ||
        source.isEmpty ||
        source.length > 25 ||
        model.isEmpty ||
        model.length > 500) {
      throw WatchChatException(T('i18n.invalid_watch_conversation_context'));
    }
    final history = <ChatMessage>[];
    for (final item in source) {
      if (item is! Map ||
          (item['role'] != 'user' && item['role'] != 'assistant') ||
          item['content'] is! String ||
          (item['content'] as String).length > 100000) {
        throw WatchChatException(T('i18n.invalid_watch_conversation_context'));
      }
      history.add(
        ChatMessage(
          id: 0,
          topicId: 0,
          role: item['role'] as String,
          content: item['content'] as String,
          createdAt: 0,
        ),
      );
    }
    if (history.last.role != 'user') {
      throw WatchChatException(T('i18n.invalid_watch_conversation_context'));
    }
    final providers = await store.providers();
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) throw WatchChatException(T('i18n.the_phone_model_service_changed'));
    final key = await store.apiKey(providerId);
    if (key == null || key.isEmpty) {
      throw WatchChatException(T('i18n.no_text_model_key_configured'));
    }
    final client = ModelApiClient(provider, key);
    final answer = StringBuffer();
    var lastPublished = 0;
    var searched = false;
    final clock = Stopwatch()..start();
    try {
      await for (final chunk in client.streamReply(
        history,
        model,
        systemPrompt: await store.systemPrompt(providerId, model),
        requireComplete: requireComplete,
        webSearch: await _webSearch(
          enabled: searchEnabled,
          providerId: searchProviderId,
        ),
        onSearchResults: (_) => searched = true,
      )) {
        answer.write(chunk);
        if (answer.length > 100000) throw WatchChatException(T('i18n.the_model_reply_is_too'));
        if (clock.elapsedMilliseconds - lastPublished >= 500) {
          lastPublished = clock.elapsedMilliseconds;
          await onUpdate({'stage': 'replying', 'answer': answer.toString()});
        }
      }
      if (answer.isEmpty) throw WatchChatException(T('i18n.the_model_did_not_return'));
      await onUpdate({'stage': 'complete', 'answer': answer.toString()});
    } catch (error) {
      await onUpdate({
        'stage': 'error',
        'error': switch (error) {
          ApiException() => error.message,
          SearchException() => error.message,
          WatchChatException() => error.message,
          _ => T('i18n.watch_phone_model_failed'),
        },
        'networkFailure':
            answer.isEmpty && !searched && _isNetworkFailure(error),
        'retrySafe': answer.isEmpty && !searched && watchRetrySafe(error),
      });
    } finally {
      clock.stop();
      client.cancel();
    }
  }

  Future<WatchAudio> remoteSpeak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || clean.runes.length > 1800) {
      throw WatchChatException(T('i18n.speech_text_is_invalid'));
    }
    final tts = await _selectedVoice('voice_tts_id');
    if (tts == null) throw WatchChatException(T('i18n.configure_speech_synthesis'));
    final key = await store.voiceApiKey(tts);
    if (key == null || key.isEmpty) {
      throw WatchChatException(T('i18n.no_speech_synthesis_key_configured'));
    }
    final client = VoiceClient(tts, key);
    try {
      return (
        bytes: await client.synthesize(clean),
        format: tts.protocol == VoiceProtocol.mimo ? 'wav' : 'mp3',
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, Object?>> configuration({bool includeKeys = true}) async {
    await StorefrontPolicy.instance.refresh();
    final providers = await store.providers();
    final selection = await loadWatchChatSelection(store);
    final provider =
        providers.where((p) => p.id == selection?.providerId).firstOrNull ??
        providers.firstOrNull;
    final model = provider == null
        ? ''
        : provider.id == selection?.providerId
        ? selection!.model
        : provider.model;
    final blocked =
        provider != null &&
        StorefrontPolicy.instance.blocks(
          provider.baseUrl,
          presetId: provider.presetId, model: model
        );
    final key = provider == null || blocked
        ? null
        : await store.apiKey(provider.id);
    Future<Map<String, Object?>?> voice(String settingKey) async {
      final selected = await _selectedVoice(settingKey);
      if (selected == null ||
          StorefrontPolicy.instance.blocks(selected.baseUrl, model: settingKey == 'voice_asr_id' ? selected.asrModel : selected.ttsModel)) {
        return null;
      }
      final voiceKey = await store.voiceApiKey(selected);
      if (voiceKey == null ||
          voiceKey.trim().isEmpty ||
          (settingKey == 'voice_asr_id' ? selected.asrModel : selected.ttsModel)
              .trim()
              .isEmpty ||
          !_validEndpoint(selected.baseUrl)) {
        return null;
      }
      return {
        'providerName': selected.name,
        'protocol': selected.protocol.name,
        'baseUrl': selected.baseUrl,
        'asrModel': selected.asrModel,
        'ttsModel': selected.ttsModel,
        'voice': selected.voice,
        'apiKey': voiceKey,
      };
    }

    final search = await store.selectedSearchProvider();
    final searchKey = search == null
        ? null
        : await store.searchApiKey(search.id);
    final searchReady =
        search != null &&
        searchKey?.trim().isNotEmpty == true &&
        _validEndpoint(search.endpoint);
    final asr = await voice('voice_asr_id');
    final textReady =
        provider != null &&
        key != null &&
        key.trim().isNotEmpty &&
        model.trim().isNotEmpty &&
        _validEndpoint(provider.baseUrl);
    return {
      'openAIRestricted': StorefrontPolicy.instance.restricted,
      'providerName': provider?.name ?? '',
      'model': model,
      'textReady': textReady,
      'asrReady': asr != null,
      'searchEnabled': await store.setting('search_enabled') == '1',
      'searchReady': searchReady,
      'searchProviderName': search?.name ?? '',
      'searchService': search?.service.name ?? '',
      if (includeKeys) ...{
        'version': 1,
        'providerId': provider?.id,
        'providerPresetId': provider?.presetId,
        'protocol': provider?.protocol.value,
        'baseUrl': provider?.baseUrl,
        'apiKey': key,
        'systemPrompt': provider == null
            ? ''
            : await store.systemPrompt(provider.id, model),
        'asr': asr,
        'tts': await voice('voice_tts_id'),
        'search': search == null
            ? null
            : {...search.toJson(), 'apiKey': searchKey},
      },
      'autoSend': VoiceSendPreference.autoSend(
        await store.setting(VoiceSendPreference.key),
      ),
      'speak': await store.setting('watch_tts_enabled') == '1',
    };
  }

  Future<({SearchProviderConfig config, String apiKey})?> _webSearch({
    bool? enabled,
    String? providerId,
  }) async {
    if (!(enabled ?? (await store.setting('search_enabled') == '1'))) {
      return null;
    }
    final config = providerId == null
        ? await store.selectedSearchProvider()
        : (await store.searchProviders())
              .where((item) => item.id == providerId)
              .firstOrNull;
    final key = config == null ? null : await store.searchApiKey(config.id);
    if (config == null || key == null || key.trim().isEmpty) {
      throw WatchChatException(T('i18n.configure_web_search'));
    }
    return (config: config, apiKey: key);
  }

  Future<void> syncTurn(String raw) async {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw WatchChatException(T('i18n.invalid_watch_conversation_format'));
    }
    await store.saveWatchTurn(value);
  }

  /// Keys are checked on the phone; only readiness and display metadata leave it.
  Future<Map<String, Object?>> preferences() =>
      configuration(includeKeys: false);

  bool _validEndpoint(String value) {
    try {
      validateBaseUrl(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<void> _requireRecordingSetup() async {
    final setup = await preferences();
    if (setup['textReady'] != true && setup['asrReady'] != true) {
      throw WatchChatException(T('i18n.configure_text_and_transcription_services'));
    }
    if (setup['textReady'] != true) {
      throw WatchChatException(T('i18n.configure_a_text_service_model'));
    }
    if (setup['asrReady'] != true) {
      throw WatchChatException(T('i18n.configure_a_transcription_service_model'));
    }
  }

  Future<void> process(
    Uint8List audio, {
    bool? autoSend,
    bool? speak,
    required WatchUpdate onUpdate,
  }) async {
    if (audio.isEmpty || audio.length > 4 * 1024 * 1024) {
      throw WatchChatException(T('i18n.invalid_recording_or_recording_exceeds'));
    }
    await _requireRecordingSetup();
    final asr = await _selectedVoice('voice_asr_id');
    if (asr == null) throw WatchChatException(T('i18n.configure_transcription_on_your_phone'));
    final asrKey = await store.voiceApiKey(asr);
    if (asrKey == null || asrKey.isEmpty) {
      throw WatchChatException(T('i18n.no_transcription_key_configured'));
    }

    final asrClient = VoiceClient(asr, asrKey);
    late final String transcript;
    try {
      transcript = await asrClient.transcribe(audio);
    } finally {
      asrClient.close();
    }
    await onUpdate({'stage': 'transcribed', 'transcript': transcript});

    if (!(autoSend ??
        VoiceSendPreference.autoSend(
          await store.setting(VoiceSendPreference.key),
        ))) {
      await onUpdate({
        'stage': 'awaiting_confirmation',
        'transcript': transcript,
      });
      return;
    }
    await sendTranscript(transcript, speak: speak, onUpdate: onUpdate);
  }

  Future<void> sendTranscript(
    String text, {
    bool? speak,
    required WatchUpdate onUpdate,
  }) async {
    final transcript = validateTranscript(text);
    await _requireRecordingSetup();

    final providers = await store.providers();
    final selection = await loadWatchChatSelection(store);
    final provider =
        providers.where((p) => p.id == selection?.providerId).firstOrNull ??
        providers.firstOrNull;
    if (provider == null) {
      throw WatchChatException(T('i18n.configure_a_text_model_service'));
    }
    final model = provider.id == selection?.providerId
        ? selection!.model
        : provider.model;
    final key = await store.apiKey(provider.id);
    if (key == null || key.isEmpty) {
      throw WatchChatException(T('i18n.no_text_model_key_configured'));
    }

    final previousId = int.tryParse(
      await store.setting('watch_topic_id') ?? '',
    );
    final previous = previousId == null
        ? null
        : (await store.topics()).where((t) => t.id == previousId).firstOrNull;
    final previousMessages = previous == null
        ? <ChatMessage>[]
        : await store.messages(previous.id);
    final canContinue =
        previous != null &&
        previous.providerId == provider.id &&
        previous.model == model &&
        previousMessages.lastOrNull?.role == 'assistant';
    final topicId = canContinue
        ? previous.id
        : await store.createTopicWithMessage(provider, model, transcript);
    if (!canContinue) {
      await store.saveSetting('watch_topic_id', '$topicId');
    } else {
      await store.addMessage(
        topicId,
        'user',
        transcript,
        modelId: model,
        provider: provider,
      );
    }
    await onUpdate({'stage': 'thinking', 'transcript': transcript});

    final history = await store.messages(topicId);
    final systemPrompt = await store.systemPrompt(provider.id, model);
    final client = ModelApiClient(provider, key);
    final clock = Stopwatch()..start();
    ReplyUsage? usage;
    List<SearchSource> sources = const [];
    int? firstTokenMs;
    final answer = StringBuffer();
    var lastPublished = 0;
    try {
      await for (final chunk in client.streamReply(
        history,
        model,
        systemPrompt: systemPrompt,
        onUsage: (value) => usage = (usage ?? const ReplyUsage()).merge(value),
        webSearch: await _webSearch(),
        onSearchResults: (value) => sources = value,
      )) {
        firstTokenMs ??= clock.elapsedMilliseconds;
        answer.write(chunk);
        if (clock.elapsedMilliseconds - lastPublished >= 300) {
          lastPublished = clock.elapsedMilliseconds;
          await onUpdate({
            'stage': 'replying',
            'transcript': transcript,
            'answer': readableMarkdown(answer.toString()),
          });
        }
      }
    } finally {
      clock.stop();
      client.cancel();
      if (answer.isNotEmpty) {
        await store.addMessage(
          topicId,
          'assistant',
          answer.toString(),
          modelId: model,
          provider: provider,
          firstTokenMs: firstTokenMs,
          totalMs: clock.elapsedMilliseconds,
          inputTokens: usage?.inputTokens,
          outputTokens: usage?.outputTokens,
          searchSources: sources,
        );
      }
    }
    if (answer.isEmpty) throw WatchChatException(T('i18n.the_model_did_not_return'));
    final complete = answer.toString();
    await onUpdate({
      'stage': 'complete',
      'transcript': transcript,
      'answer': readableMarkdown(complete),
    });

    final titleFuture = history.length == 1
        ? _generateTitle(topicId, provider, key, model, transcript, complete)
        : Future<void>.value();
    if (!(speak ?? (await store.setting('watch_tts_enabled') == '1'))) {
      await titleFuture;
      return;
    }
    final tts = await _selectedVoice('voice_tts_id');
    if (tts == null) {
      await titleFuture;
      return;
    }
    final ttsKey = await store.voiceApiKey(tts);
    if (ttsKey == null || ttsKey.isEmpty) {
      await titleFuture;
      return;
    }
    final speech = readableMarkdown(complete);
    if (speech.isEmpty) {
      await titleFuture;
      return;
    }
    final ttsClient = VoiceClient(tts, ttsKey);
    try {
      final bytes = await ttsClient.synthesize(
        speech.runes.length > 1800
            ? String.fromCharCodes(speech.runes.take(1800))
            : speech,
      );
      await onUpdate({
        'stage': 'complete',
        'transcript': transcript,
        'answer': readableMarkdown(complete),
        'audio': bytes,
        'audioFormat': tts.protocol == VoiceProtocol.mimo ? 'wav' : 'mp3',
      });
    } catch (_) {
      // Text is already saved and visible; speech is optional.
    } finally {
      ttsClient.close();
      await titleFuture;
    }
  }

  Future<VoiceProviderConfig?> _selectedVoice(String key) async {
    final selected = await store.setting(key);
    return (await store.voiceProviders())
        .where((service) => service.id == selected)
        .firstOrNull;
  }

  Future<void> _generateTitle(
    int topicId,
    ProviderConfig provider,
    String key,
    String model,
    String transcript,
    String answer,
  ) async {
    final client = ModelApiClient(provider, key);
    try {
      final title = await client
          .generateTopicTitle(model, transcript, answer)
          .timeout(const Duration(seconds: 20));
      if (title != null) {
        await store.updateTopicTitleIfUnchanged(
          topicId,
          initialTopicTitle(transcript),
          title,
        );
      }
    } catch (_) {
      // First-message title remains available.
    } finally {
      client.cancel();
    }
  }
}

class WatchChatException implements Exception {
  const WatchChatException(this.message);
  final String message;
  @override
  String toString() => message;
}
