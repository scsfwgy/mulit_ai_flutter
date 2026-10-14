import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/data.dart';

const systemVoiceId = 'apple-system';
const systemSpeechVoiceSetting = 'system_tts_voice_id';

String? resolveVoiceSelection(
  String? saved,
  List<VoiceProviderConfig> services, {
  required bool systemAvailable,
}) {
  if (saved != null) return saved;
  if (services.length == 1) return services.single.id;
  if (systemAvailable && services.isEmpty) return systemVoiceId;
  return null;
}

Future<String?> selectedVoiceId(ChatStore store, String key) async =>
    resolveVoiceSelection(
      await store.setting(key),
      await store.voiceProviders(),
      systemAvailable: supportsSystemVoice,
    );

Future<bool> usesSystemVoice(ChatStore store, String key) async =>
    supportsSystemVoice && await selectedVoiceId(store, key) == systemVoiceId;

Future<void> initializeSystemVoiceDefaults(ChatStore store) async {
  if (!supportsSystemVoice || (await store.voiceProviders()).isNotEmpty) return;
  // Existing choices, including explicit “None” and disabled playback, survive upgrades.
  for (final key in ['voice_asr_id', 'voice_tts_id']) {
    if (await store.setting(key) == null) {
      await store.saveSetting(key, systemVoiceId);
    }
  }
  if (await store.setting('voice_tts_id') != systemVoiceId) return;
  for (final key in ['voice_auto_read', 'watch_tts_enabled']) {
    if (await store.setting(key) == null) await store.saveSetting(key, '0');
  }
}
