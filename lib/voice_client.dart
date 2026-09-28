import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'data.dart';

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
  if (clean.isEmpty) throw const VoiceException('没有识别到可用文字，请重试');
  if (clean.runes.length > 5000) throw const VoiceException('识别文字过长，请分段录音');
  return clean;
}

class VoiceClient {
  VoiceClient(this.config, this.key, {http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final VoiceProviderConfig config;
  final String key;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
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
  }) async {
    request.followRedirects = false;
    request.headers.addAll(_auth);
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 65));
    final data = <int>[];
    await for (final chunk in streamed.stream.timeout(
      const Duration(seconds: 65),
    )) {
      data.addAll(chunk);
      if (data.length > maxBytes) throw const VoiceException('语音服务返回内容过大');
    }
    final response = http.Response.bytes(
      Uint8List.fromList(data),
      streamed.statusCode,
      headers: streamed.headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceException(
        '语音服务请求失败（HTTP ${response.statusCode}），请检查密钥、模型和服务权限',
      );
    }
    return response;
  }

  Future<http.Response> _json(
    String path,
    Object body, {
    Map<String, String> headers = const {},
    int maxBytes = 2 * 1024 * 1024,
  }) {
    final request = http.Request('POST', _endpoint(path))
      ..headers.addAll({'Content-Type': 'application/json', ...headers})
      ..body = jsonEncode(body);
    return _send(request, maxBytes: maxBytes);
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const VoiceException('语音服务返回格式无效');
    }
  }

  Future<String> transcribe(Uint8List wav) async {
    if (wav.isEmpty || wav.length > 12 * 1024 * 1024) {
      throw const VoiceException('录音为空或超过 12 MB，请缩短录音');
    }
    if (key.trim().isEmpty) throw const VoiceException('语音服务缺少 API Key');
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
        body = _decode(await _send(request));
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
          }),
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
        );
        final status = response.headers['x-api-status-code'];
        if (status != null && status != '20000000') {
          throw VoiceException('豆包语音识别失败（状态码 $status），请检查资源权限');
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
    if (input.isEmpty) throw const VoiceException('没有可朗读的文字');
    if (input.runes.length > 1800) {
      throw const VoiceException('消息过长，请选择较短的内容朗读');
    }
    if (key.trim().isEmpty) throw const VoiceException('语音服务缺少 API Key');
    switch (config.protocol) {
      case VoiceProtocol.openAi:
        final response = await _json('/audio/speech', {
          'model': config.ttsModel,
          'input': input,
          'voice': config.voice,
          'response_format': 'mp3',
        }, maxBytes: 16 * 1024 * 1024);
        if (response.bodyBytes.isEmpty) {
          throw const VoiceException('语音服务没有返回音频');
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
          throw const VoiceException('语音服务没有返回音频');
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
            throw VoiceException('豆包语音合成失败（状态码 $code）');
          }
          if (event['data'] case final String encoded when encoded.isNotEmpty) {
            bytes.add(_audioFromBase64(encoded));
          }
        }
        if (bytes.isEmpty) throw const VoiceException('语音服务没有返回音频');
        return bytes.toBytes();
    }
  }

  Uint8List _audioFromBase64(String source) {
    try {
      return base64Decode(source);
    } catch (_) {
      throw const VoiceException('语音服务返回的音频无效');
    }
  }
}
