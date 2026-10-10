import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

enum VoiceCatalogKind { asr, tts, voice }

class VoiceCatalogOption {
  const VoiceCatalogOption(this.id, [this.name]);
  final String id;
  final String? name;
}

/// These are documented examples, not a claim that the user's account has access.
List<VoiceCatalogOption> voiceCatalogExamples(
  VoiceProtocol protocol,
  VoiceCatalogKind kind, {
  String? ttsModel,
}) {
  switch (protocol) {
    case VoiceProtocol.doubao:
      return switch (kind) {
        VoiceCatalogKind.asr => const [
          VoiceCatalogOption('volc.bigasr.auc_turbo', 'i18n.fast_transcription'),
        ],
        VoiceCatalogKind.tts => const [
          VoiceCatalogOption('seed-tts-2.0', 'i18n.speech_synthesis_v2'),
        ],
        VoiceCatalogKind.voice => const [
          VoiceCatalogOption('zh_female_vv_uranus_bigtts', 'Vivi 2.0'),
          VoiceCatalogOption('zh_female_tianmeitaozi_mars_bigtts', 'i18n.sweet_peach'),
          VoiceCatalogOption('zh_male_dayi_saturn_bigtts', 'i18n.da_yi'),
          VoiceCatalogOption('zh_female_mizai_saturn_bigtts', 'i18n.mizai'),
          VoiceCatalogOption('zh_female_jitangnv_saturn_bigtts', 'i18n.warm_narrator'),
          VoiceCatalogOption('zh_female_meilinvyou_saturn_bigtts', 'i18n.charming_girlfriend'),
          VoiceCatalogOption('zh_female_santongyongns_saturn_bigtts', 'i18n.fluent_female_voice'),
          VoiceCatalogOption('zh_male_ruyayichen_saturn_bigtts', 'i18n.yichen'),
        ],
      };
    case VoiceProtocol.mimo:
      return switch (kind) {
        VoiceCatalogKind.asr => const [VoiceCatalogOption('mimo-v2.5-asr')],
        VoiceCatalogKind.tts => const [VoiceCatalogOption('mimo-v2.5-tts')],
        VoiceCatalogKind.voice => const [
          VoiceCatalogOption('mimo_default', 'i18n.default'),
          VoiceCatalogOption('冰糖', 'i18n.chinese_female_voice'),
          VoiceCatalogOption('茉莉', 'i18n.chinese_female_voice'),
          VoiceCatalogOption('苏打', 'i18n.chinese_male_voice'),
          VoiceCatalogOption('白桦', 'i18n.chinese_male_voice'),
          VoiceCatalogOption('Mia', 'i18n.english_female_voice'),
          VoiceCatalogOption('Chloe', 'i18n.english_female_voice'),
          VoiceCatalogOption('Milo', 'i18n.english_male_voice'),
          VoiceCatalogOption('Dean', 'i18n.english_male_voice'),
        ],
      };
    case VoiceProtocol.openAi:
      return switch (kind) {
        VoiceCatalogKind.asr => const [
          VoiceCatalogOption('gpt-transcribe'),
          VoiceCatalogOption('gpt-4o-transcribe'),
          VoiceCatalogOption('gpt-4o-mini-transcribe'),
          VoiceCatalogOption('whisper-1'),
        ],
        VoiceCatalogKind.tts => const [
          VoiceCatalogOption('gpt-4o-mini-tts'),
          VoiceCatalogOption('tts-1'),
          VoiceCatalogOption('tts-1-hd'),
        ],
        VoiceCatalogKind.voice => [
          for (final id
              in (ttsModel == 'tts-1' || ttsModel == 'tts-1-hd')
                  ? const [
                      'alloy',
                      'ash',
                      'coral',
                      'echo',
                      'fable',
                      'onyx',
                      'nova',
                      'sage',
                      'shimmer',
                    ]
                  : const [
                      'alloy',
                      'ash',
                      'ballad',
                      'coral',
                      'echo',
                      'fable',
                      'nova',
                      'onyx',
                      'sage',
                      'shimmer',
                      'verse',
                      'marin',
                      'cedar',
                    ])
            VoiceCatalogOption(id),
        ],
      };
  }
}

/// Only OpenAI-compatible /models is queried. A returned ID is not proof that
/// the service implements the audio endpoint or that the account has quota.
class VoiceCatalogClient {
  VoiceCatalogClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<VoiceCatalogOption>> fetchModels({
    required String baseUrl,
    required String apiKey,
    required VoiceProtocol protocol,
    required VoiceCatalogKind kind,
  }) async {
    if (protocol == VoiceProtocol.doubao || kind == VoiceCatalogKind.voice) {
      return const [];
    }
    if (apiKey.trim().isEmpty) {
      throw FormatException(T('i18n.enter_an_api_key_first'));
    }
    await StorefrontPolicy.instance.requireAllowed(baseUrl);
    final root = validateBaseUrl(baseUrl);
    final request = http.Request('GET', Uri.parse('$root/models'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..headers['Accept'] = 'application/json';
    try {
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw FormatException(F('i18n.voice_catalog_http_failed', [response.statusCode]));
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw FormatException(T('i18n.model_list_is_too_large'));
        }
      }
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw FormatException(T('i18n.the_service_has_no_model'));
      }
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) throw FormatException(T('i18n.the_service_has_no_model'));
      final ids = <String>{};
      for (final item in data) {
        if (item is! Map || item['id'] is! String) continue;
        final id = (item['id'] as String).trim();
        final lower = id.toLowerCase();
        final matches = protocol == VoiceProtocol.mimo
            ? id ==
                  (kind == VoiceCatalogKind.asr
                      ? 'mimo-v2.5-asr'
                      : 'mimo-v2.5-tts')
            : kind == VoiceCatalogKind.asr
            ? lower.contains('transcri') ||
                  lower.contains('whisper') ||
                  lower.endsWith('-asr')
            : lower.contains('tts') || lower.contains('speech');
        if (id.isNotEmpty && id.length <= 160 && matches &&
            !(StorefrontPolicy.instance.restricted && StorefrontPolicy.isOpenAIModel(id))) {
          ids.add(id);
        }
      }
      return [for (final id in ids.toList()..sort()) VoiceCatalogOption(id)];
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException(T('i18n.model_list_unavailable_manual'));
    }
  }
}
