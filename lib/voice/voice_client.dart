import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/voice/voice_request_diagnostics.dart';

class VoiceException implements Exception {
  const VoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

String validateTranscript(String text) {
  final clean = text
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .trim();
  if (clean.isEmpty) throw VoiceException(T('i18n.no_usable_speech_was_detected'));
  if (clean.runes.length > 5000) throw VoiceException(T('i18n.transcript_too_long_record_shorter'));
  return clean;
}

class VoiceClient {
  VoiceClient(this.config, this.key, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null {
    StorefrontPolicy.instance.addListener(_storefrontChanged);
  }

  final VoiceProviderConfig config;
  final String key;
  final http.Client _client;
  final bool _ownsClient;
  Map<String, Object?>? _audioDiagnostics;

  void _trace(String id, String event, Map<String, Object?> details) {
    if (!kDebugMode) return;
    // Also redact accidental secret echoes in model IDs or endpoint paths.
    var line = jsonEncode({'event': event, ...details});
    for (final secret in [
      key,
      Uri.encodeComponent(key),
      base64Encode(utf8.encode(key)),
    ]) {
      if (secret.isNotEmpty) {
        line = line.replaceAll(secret, '<redacted>');
        line = line.replaceAll(
          jsonEncode(secret).substring(1, jsonEncode(secret).length - 1),
          '<redacted>',
        );
      }
    }
    debugPrint('[AI Link Voice][$id] $line');
  }

  void _storefrontChanged() {
    if (StorefrontPolicy.instance.blocks(config.baseUrl, model: config.asrModel) ||
        StorefrontPolicy.instance.blocks(config.baseUrl, model: config.ttsModel)) {
      close();
    }
  }

  void close() {
    StorefrontPolicy.instance.removeListener(_storefrontChanged);
    if (_ownsClient) _client.close();
  }

  Uri get _root => Uri.parse(validateBaseUrl(config.baseUrl));
  Uri _endpoint(String suffix) => Uri.parse('${_root.toString()}$suffix');

  Map<String, String> get _auth => config.protocol == VoiceProtocol.doubao
      ? {'X-Api-Key': key}
      : {'Authorization': 'Bearer $key'};

  Future<http.Response> _send(
    http.BaseRequest request, {
    int maxBytes = 2 * 1024 * 1024,
    String operation = 'i18n.voice_operation_service',
  }) async {
    try {
      await StorefrontPolicy.instance.requireAllowed(config.baseUrl, model: operation == 'i18n.voice_operation_transcription' ? config.asrModel : config.ttsModel);
    } on StorefrontRestrictedException catch (error) {
      throw VoiceException(error.message);
    }
    request.followRedirects = false;
    request.headers.addAll(_auth);
    final traceId = const Uuid().v4();
    final watch = Stopwatch()..start();
    if (kDebugMode) {
      _trace(traceId, 'request', {
        'operation': T(operation),
        'protocol': config.protocol.name,
        ...voiceRequestDiagnostics(request),
        if (operation == 'i18n.voice_operation_transcription')
          'recording': _audioDiagnostics,
      });
    }
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 65));
    _trace(traceId, 'response', {
      'http_status': streamed.statusCode,
      'headers_ms': watch.elapsedMilliseconds,
      'content_type': streamed.headers['content-type'],
    });
    final failed = streamed.statusCode < 200 || streamed.statusCode >= 300;
    // Error bodies can echo credentials and need only a bounded structured code.
    final limit = failed ? 4096 : maxBytes;
    final data = <int>[];
    await for (final chunk in streamed.stream.timeout(
      const Duration(seconds: 65),
    )) {
      if (data.length + chunk.length > limit) {
        if (!failed) throw VoiceException(T('i18n.voice_service_response_is_too'));
        data.addAll(chunk.take(limit - data.length));
        break;
      }
      data.addAll(chunk);
    }
    final response = http.Response.bytes(
      Uint8List.fromList(data),
      streamed.statusCode,
      headers: streamed.headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final reason = switch (response.statusCode) {
        401 || 403 => 'i18n.voice_error_auth',
        429 => 'i18n.voice_error_rate_limit',
        >= 500 => 'i18n.voice_error_server',
        400 || 404 || 422 => 'i18n.voice_error_request',
        >= 300 && < 400 => 'i18n.voice_error_redirect',
        _ => 'i18n.voice_error_generic',
      };
      // Never display the raw response or server-provided message.
      String? code;
      try {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final error = json is Map ? json['error'] : null;
        final value = error is Map ? error['code'] : null;
        final candidate = value?.toString();
        if (candidate != null &&
            RegExp(r'^[a-zA-Z0-9_.-]{1,64}$').hasMatch(candidate) &&
            !candidate.contains(key) &&
            !candidate.contains(base64Encode(utf8.encode(key)))) {
          code = candidate;
        }
      } catch (_) {
        // Invalid or truncated JSON stays a generic HTTP error.
      }
      _trace(traceId, 'error', {
        'http_status': response.statusCode,
        'elapsed_ms': watch.elapsedMilliseconds,
        'response_bytes': response.bodyBytes.length,
        'error_code': code,
      });
      throw VoiceException(
        F('i18n.voice_http_failed', [
          T(operation),
          response.statusCode,
          T(reason),
          code == null ? '' : F('i18n.voice_http_failed_code', [code]),
        ]),
      );
    }
    _trace(traceId, 'complete', {
      'http_status': response.statusCode,
      'elapsed_ms': watch.elapsedMilliseconds,
      'response_bytes': response.bodyBytes.length,
    });
    return response;
  }

  Future<http.Response> _json(
    String path,
    Object body, {
    Map<String, String> headers = const {},
    int maxBytes = 2 * 1024 * 1024,
    String operation = 'i18n.voice_operation_speech',
  }) {
    final request = http.Request('POST', _endpoint(path))
      ..headers.addAll({'Content-Type': 'application/json', ...headers})
      ..body = jsonEncode(body);
    return _send(request, maxBytes: maxBytes, operation: operation);
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw VoiceException(T('i18n.invalid_voice_service_response'));
    }
  }

  Future<String> transcribe(Uint8List wav) async {
    if (wav.isEmpty || wav.length > 12 * 1024 * 1024) {
      throw VoiceException(T('i18n.recording_empty_or_too_large'));
    }
    if (key.trim().isEmpty) throw VoiceException(T('i18n.voice_service_api_key'));
    final audio = voiceWavDiagnostics(wav, includeLevels: kDebugMode);
    if (kDebugMode) _audioDiagnostics = audio;
    if (audio['container'] != 'RIFF/WAVE' ||
        (audio['data_actual_bytes'] as int? ?? 0) == 0 ||
        audio['data_truncated'] == true ||
        audio['truncated_chunk'] == true) {
      _trace(const Uuid().v4(), 'audio_rejected', {'recording': audio});
      throw VoiceException(T('i18n.recording_contains_no_valid_audio'));
    }
    late final Map<String, dynamic> body;
    switch (config.protocol) {
      case VoiceProtocol.openAi:
        final request =
            http.MultipartRequest('POST', _endpoint('/audio/transcriptions'))
              ..fields['model'] = config.asrModel
              ..files.add(
                http.MultipartFile.fromBytes(
                  'file',
                  wav,
                  filename: 'speech.wav',
                  contentType: http.MediaType('audio', 'wav'),
                ),
              );
        body = _decode(await _send(request, operation: 'i18n.voice_operation_transcription'));
        return validateTranscript(
          body['text'] is String ? body['text'] as String : '',
        );
      case VoiceProtocol.mimo:
        body = _decode(
          await _json('/chat/completions', {
            'model': config.asrModel,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'input_audio',
                    'input_audio': {
                      'data': 'data:audio/wav;base64,${base64Encode(wav)}',
                      'format': 'wav',
                    },
                  },
                ],
              },
            ],
            'asr_options': {'language': 'auto'},
          }, operation: 'i18n.voice_operation_transcription'),
        );
        final choices = body['choices'];
        final message = choices is List && choices.isNotEmpty
            ? choices.first['message']
            : null;
        return validateTranscript(
          message is Map ? (message['content'] as String? ?? '') : '',
        );
      case VoiceProtocol.doubao:
        final response = await _json(
          '/api/v3/auc/bigmodel/recognize/flash',
          {
            'user': {'uid': 'between-models'},
            'audio': {'data': base64Encode(wav), 'format': 'wav'},
            'request': {'model_name': 'bigmodel'},
          },
          headers: {
            'X-Api-Resource-Id': config.asrModel,
            'X-Api-Request-Id': const Uuid().v4(),
            'X-Api-Sequence': '-1',
          },
          operation: 'i18n.voice_operation_transcription',
        );
        final status = response.headers['x-api-status-code'];
        if (status != null && status != '20000000') {
          throw VoiceException(F('i18n.doubao_asr_failed', [status]));
        }
        body = _decode(response);
        final result = body['result'];
        return validateTranscript(
          result is Map ? (result['text'] as String? ?? '') : '',
        );
    }
  }

  Future<Uint8List> synthesize(String text) async {
    final input = text.trim();
    if (input.isEmpty) throw VoiceException(T('i18n.no_text_to_read_aloud'));
    if (input.runes.length > 1800) {
      throw VoiceException(T('i18n.message_too_long_choose_shorter'));
    }
    if (key.trim().isEmpty) throw VoiceException(T('i18n.voice_service_api_key'));
    switch (config.protocol) {
      case VoiceProtocol.openAi:
        final response = await _json('/audio/speech', {
          'model': config.ttsModel,
          'input': input,
          'voice': config.voice,
          'response_format': 'mp3',
        }, maxBytes: 16 * 1024 * 1024);
        if (response.bodyBytes.isEmpty) {
          throw VoiceException(T('i18n.voice_service_returned_no_audio'));
        }
        return response.bodyBytes;
      case VoiceProtocol.mimo:
        final body = _decode(
          await _json('/chat/completions', {
            'model': config.ttsModel,
            'messages': [
              {'role': 'assistant', 'content': input},
            ],
            'audio': {'format': 'wav', 'voice': config.voice},
          }, maxBytes: 20 * 1024 * 1024),
        );
        final choices = body['choices'];
        final message = choices is List && choices.isNotEmpty
            ? choices.first['message']
            : null;
        final audio = message is Map ? message['audio'] : null;
        final encoded = audio is Map ? audio['data'] : null;
        if (encoded is! String || encoded.isEmpty) {
          throw VoiceException(T('i18n.voice_service_returned_no_audio'));
        }
        return _audioFromBase64(encoded);
      case VoiceProtocol.doubao:
        final response = await _json(
          '/api/v3/tts/unidirectional/sse',
          {
            'user': {'uid': 'between-models'},
            'req_params': {
              'text': input,
              'speaker': config.voice,
              'audio_params': {'format': 'mp3', 'sample_rate': 24000},
            },
          },
          headers: {
            'X-Api-Resource-Id': config.ttsModel,
            'X-Api-Request-Id': const Uuid().v4(),
          },
          maxBytes: 24 * 1024 * 1024,
        );
        final bytes = BytesBuilder();
        for (final line in const LineSplitter().convert(
          utf8.decode(response.bodyBytes),
        )) {
          if (!line.startsWith('data:')) continue;
          Map<String, dynamic> event;
          try {
            event =
                jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final code = event['code'];
          if (code != null && code != 0 && code != 20000000) {
            throw VoiceException(F('i18n.doubao_tts_failed', [code]));
          }
          if (event['data'] case final String encoded when encoded.isNotEmpty) {
            bytes.add(_audioFromBase64(encoded));
          }
        }
        if (bytes.isEmpty) throw VoiceException(T('i18n.voice_service_returned_no_audio'));
        return bytes.toBytes();
    }
  }

  Uint8List _audioFromBase64(String source) {
    try {
      return base64Decode(source);
    } catch (_) {
      throw VoiceException(T('i18n.voice_service_returned_invalid_audio'));
    }
  }
}
