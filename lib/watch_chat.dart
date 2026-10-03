import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'data.dart';
import 'message_copy.dart';
import 'voice_client.dart';
import 'voice_send_preference.dart';

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
        channel.invokeMethod<void>('publish', {'id': requestId, ...update});
    try {
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
        throw const WatchChatException('手表请求无效');
      }
    } catch (error) {
      if (kind == 'config' || kind == 'turn') rethrow;
      final message = switch (error) {
        WatchChatException() => error.message,
        VoiceException() => error.message,
        ApiException() => error.message,
        _ => '手机处理请求失败，请重试',
      };
      await publish({
        'stage': 'error',
        'error': message,
        'networkFailure': _isNetworkFailure(error),
      });
    }
  });
  channel.invokeMethod<void>('ready');
}

typedef WatchUpdate = Future<void> Function(Map<String, Object?> update);

bool _isNetworkFailure(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HttpException ||
    error is http.ClientException ||
    (error is ApiException && error.kind == ApiErrorKind.network);

typedef WatchAudio = ({Uint8List bytes, String format});

class WatchChatProcessor {
  WatchChatProcessor({ChatStore? store}) : store = store ?? ChatStore.instance;

  final ChatStore store;

  /// Phone network execution for a watch-owned turn. These methods never write
  /// the conversation; the watch stores one result and syncs it afterward.
  Future<String> remoteTranscribe(Uint8List audio) async {
    if (audio.isEmpty || audio.length > 4 * 1024 * 1024) {
      throw const WatchChatException('录音无效或超过大小限制');
    }
    await _requireRecordingSetup();
    final asr = await _selectedVoice('voice_asr_id');
    if (asr == null) throw const WatchChatException('请先在手机端配置语音识别服务');
    final key = await store.voiceApiKey(asr);
    if (key == null || key.isEmpty) {
      throw const WatchChatException('手机端语音识别密钥未配置');
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
    required WatchUpdate onUpdate,
  }) async {
    final source = jsonDecode(rawHistory);
    if (source is! List ||
        source.isEmpty ||
        source.length > 25 ||
        model.isEmpty ||
        model.length > 500) {
      throw const WatchChatException('手表会话上下文无效');
    }
    final history = <ChatMessage>[];
    for (final item in source) {
      if (item is! Map ||
          (item['role'] != 'user' && item['role'] != 'assistant') ||
          item['content'] is! String ||
          (item['content'] as String).length > 100000) {
        throw const WatchChatException('手表会话上下文无效');
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
      throw const WatchChatException('手表会话上下文无效');
    }
    final providers = await store.providers();
    final provider = providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) throw const WatchChatException('手机端模型服务已变更，请同步手表配置');
    final key = await store.apiKey(providerId);
    if (key == null || key.isEmpty) {
      throw const WatchChatException('手机端文字模型密钥未配置');
    }
    final client = ModelApiClient(provider, key);
    final answer = StringBuffer();
    var lastPublished = 0;
    final clock = Stopwatch()..start();
    try {
      await for (final chunk in client.streamReply(
        history,
        model,
        systemPrompt: await store.systemPrompt(providerId, model),
      )) {
        answer.write(chunk);
        if (answer.length > 100000) throw const WatchChatException('模型回复过长');
        if (clock.elapsedMilliseconds - lastPublished >= 500) {
          lastPublished = clock.elapsedMilliseconds;
          await onUpdate({'stage': 'replying', 'answer': answer.toString()});
        }
      }
      if (answer.isEmpty) throw const WatchChatException('模型没有返回文字');
      await onUpdate({'stage': 'complete', 'answer': answer.toString()});
    } catch (error) {
      await onUpdate({
        'stage': 'error',
        'error': error is ApiException ? error.message : '手机模型请求失败',
        'networkFailure': answer.isEmpty && _isNetworkFailure(error),
      });
    } finally {
      clock.stop();
      client.cancel();
    }
  }

  Future<WatchAudio> remoteSpeak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || clean.runes.length > 1800) {
      throw const WatchChatException('朗读文字无效或过长');
    }
    final tts = await _selectedVoice('voice_tts_id');
    if (tts == null) throw const WatchChatException('请先在手机端配置朗读服务');
    final key = await store.voiceApiKey(tts);
    if (key == null || key.isEmpty) {
      throw const WatchChatException('手机端朗读服务密钥未配置');
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
    final providers = await store.providers();
    final selection = await loadWatchChatSelection(store);
    final provider =
        providers.where((p) => p.id == selection?.providerId).firstOrNull ??
        providers.firstOrNull;
    final key = provider == null ? null : await store.apiKey(provider.id);
    final model = provider == null
        ? ''
        : provider.id == selection?.providerId
        ? selection!.model
        : provider.model;
    Future<Map<String, Object?>?> voice(String settingKey) async {
      final selected = await _selectedVoice(settingKey);
      if (selected == null) return null;
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
        'protocol': selected.protocol.name,
        'baseUrl': selected.baseUrl,
        'asrModel': selected.asrModel,
        'ttsModel': selected.ttsModel,
        'voice': selected.voice,
        'apiKey': voiceKey,
      };
    }

    final asr = await voice('voice_asr_id');
    final textReady =
        provider != null &&
        key != null &&
        key.trim().isNotEmpty &&
        model.trim().isNotEmpty &&
        _validEndpoint(provider.baseUrl);
    return {
      'providerName': provider?.name ?? '',
      'model': model,
      'textReady': textReady,
      'asrReady': asr != null,
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
      },
      'autoSend': VoiceSendPreference.autoSend(
        await store.setting(VoiceSendPreference.key),
      ),
      'speak': await store.setting('watch_tts_enabled') == '1',
    };
  }

  Future<void> syncTurn(String raw) async {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const WatchChatException('手表会话格式无效');
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
      throw const WatchChatException('请先在手机端配置文字模型和语音识别服务及密钥');
    }
    if (setup['textReady'] != true) {
      throw const WatchChatException('请先在手机端配置文字模型服务、模型和密钥');
    }
    if (setup['asrReady'] != true) {
      throw const WatchChatException('请先在手机端配置语音识别服务、识别模型和密钥');
    }
  }

  Future<void> process(
    Uint8List audio, {
    bool? autoSend,
    bool? speak,
    required WatchUpdate onUpdate,
  }) async {
    if (audio.isEmpty || audio.length > 4 * 1024 * 1024) {
      throw const WatchChatException('录音无效或超过大小限制');
    }
    await _requireRecordingSetup();
    final asr = await _selectedVoice('voice_asr_id');
    if (asr == null) throw const WatchChatException('请先在手机端配置语音识别服务');
    final asrKey = await store.voiceApiKey(asr);
    if (asrKey == null || asrKey.isEmpty) {
      throw const WatchChatException('手机端语音识别密钥未配置');
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
      throw const WatchChatException('请先在手机端配置文字模型服务');
    }
    final model = provider.id == selection?.providerId
        ? selection!.model
        : provider.model;
    final key = await store.apiKey(provider.id);
    if (key == null || key.isEmpty) {
      throw const WatchChatException('手机端文字模型密钥未配置');
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
    int? firstTokenMs;
    final answer = StringBuffer();
    var lastPublished = 0;
    try {
      await for (final chunk in client.streamReply(
        history,
        model,
        systemPrompt: systemPrompt,
        onUsage: (value) => usage = (usage ?? const ReplyUsage()).merge(value),
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
        );
      }
    }
    if (answer.isEmpty) throw const WatchChatException('模型没有返回文字');
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
