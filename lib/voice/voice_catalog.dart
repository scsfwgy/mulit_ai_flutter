import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:mulit_ai_flutter/core/data.dart';

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
          VoiceCatalogOption('volc.bigasr.auc_turbo', '录音识别极速版'),
        ],
        VoiceCatalogKind.tts => const [
          VoiceCatalogOption('seed-tts-2.0', '语音合成 2.0'),
        ],
        VoiceCatalogKind.voice => const [
          VoiceCatalogOption('zh_female_vv_uranus_bigtts', 'Vivi 2.0'),
          VoiceCatalogOption('zh_female_tianmeitaozi_mars_bigtts', '甜美桃子'),
          VoiceCatalogOption('zh_male_dayi_saturn_bigtts', '大壹'),
          VoiceCatalogOption('zh_female_mizai_saturn_bigtts', '黑猫侦探社咪仔'),
          VoiceCatalogOption('zh_female_jitangnv_saturn_bigtts', '鸡汤女'),
          VoiceCatalogOption('zh_female_meilinvyou_saturn_bigtts', '魅力女友'),
          VoiceCatalogOption('zh_female_santongyongns_saturn_bigtts', '流畅女声'),
          VoiceCatalogOption('zh_male_ruyayichen_saturn_bigtts', '儒雅逸辰'),
        ],
      };
    case VoiceProtocol.mimo:
      return switch (kind) {
        VoiceCatalogKind.asr => const [VoiceCatalogOption('mimo-v2.5-asr')],
        VoiceCatalogKind.tts => const [VoiceCatalogOption('mimo-v2.5-tts')],
        VoiceCatalogKind.voice => const [
          VoiceCatalogOption('mimo_default', '默认'),
          VoiceCatalogOption('冰糖', '中文女声'),
          VoiceCatalogOption('茉莉', '中文女声'),
          VoiceCatalogOption('苏打', '中文男声'),
          VoiceCatalogOption('白桦', '中文男声'),
          VoiceCatalogOption('Mia', '英文女声'),
          VoiceCatalogOption('Chloe', '英文女声'),
          VoiceCatalogOption('Milo', '英文男声'),
          VoiceCatalogOption('Dean', '英文男声'),
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
    if (apiKey.trim().isEmpty) throw const FormatException('请先填写 API Key');
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
        throw FormatException('获取模型列表失败（HTTP ${response.statusCode}）');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('模型列表过大');
        }
      }
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const FormatException('服务未提供模型列表');
      }
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) throw const FormatException('服务未提供模型列表');
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
        if (id.isNotEmpty && id.length <= 160 && matches) ids.add(id);
      }
      return [for (final id in ids.toList()..sort()) VoiceCatalogOption(id)];
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法获取模型列表，请检查网络或手动填写');
    }
  }
}
