import 'package:flutter/services.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/voice/voice_client.dart';

class SystemSpeechVoice {
  const SystemSpeechVoice(
    this.identifier,
    this.name,
    this.language,
    this.quality,
  );
  final String identifier;
  final String name;
  final String language;
  final int quality;

  String get label =>
      '$name · $language · ${T(switch (quality) {
        2 => 'i18n.system_voice_enhanced',
        3 => 'i18n.system_voice_premium',
        _ => 'i18n.system_voice_standard',
      })}';
}

class SystemVoice {
  static const channel = MethodChannel('between_models/system_voice');

  static Future<Result?> _call<Result>(
    String method, [
    Object? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<Result>(method, arguments);
    } on PlatformException catch (error) {
      throw VoiceException(
        T(switch (error.code) {
          'speech_permission' => 'i18n.system_speech_permission',
          'speech_unavailable' => 'i18n.system_speech_unavailable',
          _ => 'i18n.system_voice_failed',
        }),
      );
    } on MissingPluginException {
      throw VoiceException(T('i18n.system_speech_unavailable'));
    }
  }

  static Future<void> prepareRecognition(String locale) =>
      _call<void>('prepareRecognition', {'locale': locale});

  static Future<String> transcribe(Uint8List audio, String locale) async =>
      validateTranscript(
        await _call<String>('transcribe', {'audio': audio, 'locale': locale}) ??
            '',
      );

  static Future<List<SystemSpeechVoice>> availableVoices() async {
    final values = await _call<List<Object?>>('voices') ?? [];
    return values.map((value) {
      final item = Map<String, Object?>.from(value as Map);
      return SystemSpeechVoice(
        item['identifier'] as String,
        item['name'] as String,
        item['language'] as String,
        item['quality'] as int,
      );
    }).toList();
  }

  // Completes when speaking ends; callers keep their existing generation checks.
  static Future<void> speak(
    String text,
    String locale, {
    String? voiceIdentifier,
  }) => _call<void>('speak', {
    'text': text,
    'locale': locale,
    if (voiceIdentifier?.isNotEmpty == true) 'voiceIdentifier': voiceIdentifier,
  });

  static Future<void> stop() async {
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {
      // Best effort during disposal or an audio interruption.
    }
  }

  static Future<void> cancelRecognition() async {
    try {
      await channel.invokeMethod<void>('cancelRecognition');
    } catch (_) {}
  }
}
