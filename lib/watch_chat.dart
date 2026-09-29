import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'data.dart';
import 'message_copy.dart';
import 'voice_client.dart';
import 'voice_send_preference.dart';

/// Runs in a separate Flutter engine owned by the Android watch request worker.
/// The phone remains the only owner of providers, secrets and chat history.
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
          onUpdate: publish,
        );
      } else if (kind == 'audio') {
        await processor.process(args['audio'] as Uint8List, onUpdate: publish);
      } else {
        throw const WatchChatException('手表请求无效');
      }
    } catch (error) {
      final message = switch (error) {
        WatchChatException() => error.message,
        VoiceException() => error.message,
        ApiException() => error.message,
        _ => '手机处理请求失败，请重试',
      };
      await publish({'stage': 'error', 'error': message});
    }
  });
  channel.invokeMethod<void>('ready');
}

typedef WatchUpdate = Future<void> Function(Map<String, Object?> update);

class WatchChatProcessor {
  WatchChatProcessor({ChatStore? store}) : store = store ?? ChatStore.instance;

  final ChatStore store;

  Future<void> process(Uint8List audio, {required WatchUpdate onUpdate}) async {
    if (audio.isEmpty || audio.length > 4 * 1024 * 1024) {
      throw const WatchChatException('录音无效或超过大小限制');
    }
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

    if (!VoiceSendPreference.autoSend(
      await store.setting(VoiceSendPreference.key),
    )) {
      await onUpdate({
        'stage': 'awaiting_confirmation',
        'transcript': transcript,
      });
      return;
    }
    await sendTranscript(transcript, onUpdate: onUpdate);
  }

  Future<void> sendTranscript(
    String text, {
    required WatchUpdate onUpdate,
  }) async {
    final transcript = validateTranscript(text);

    final providers = await store.providers();
    final selectedId = int.tryParse(
      await store.setting('watch_provider_id') ?? '',
    );
    final provider =
        providers.where((p) => p.id == selectedId).firstOrNull ??
        providers.firstOrNull;
    if (provider == null) {
      throw const WatchChatException('请先在手机端配置文字模型服务');
    }
    final model = provider.id == selectedId
        ? (await store.setting('watch_model_id') ?? provider.model)
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
    if (await store.setting('watch_tts_enabled') != '1') {
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
