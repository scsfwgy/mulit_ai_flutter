import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'data.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Extracts complete SSE data payloads, including events with multiple data lines.
class SseDecoder {
  final _data = <String>[];

  String? addLine(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty) return null;
      final result = _data.join('\n');
      _data.clear();
      return result;
    }
    if (line.startsWith('data:')) {
      final value = line.substring(5);
      _data.add(value.startsWith(' ') ? value.substring(1) : value);
    }
    return null;
  }

  String? finish() {
    if (_data.isEmpty) return null;
    final result = _data.join('\n');
    _data.clear();
    return result;
  }
}

class ModelApiClient {
  ModelApiClient(this.provider, this.apiKey);
  final ProviderConfig provider;
  final String apiKey;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  void cancel() => _client.close(force: true);

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'accept': 'text/event-stream',
    if (provider.protocol == ApiProtocol.anthropic) ...{
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    } else
      'authorization': 'Bearer $apiKey',
  };

  Uri get _chatUri => Uri.parse(
    '${provider.baseUrl}/'
    '${provider.protocol == ApiProtocol.anthropic ? 'messages' : 'chat/completions'}',
  );

  Map<String, Object?> _body(List<ChatMessage> history, String model) {
    final messages = history
        .map((message) => {'role': message.role, 'content': message.content})
        .toList();
    if (provider.protocol == ApiProtocol.anthropic) {
      return {
        'model': model,
        'max_tokens': 4096,
        'stream': true,
        'messages': messages,
      };
    }
    return {'model': model, 'stream': true, 'messages': messages};
  }

  Stream<String> streamReply(List<ChatMessage> history, String model) async* {
    try {
      final request = await _client
          .postUrl(_chatUri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      _headers.forEach(request.headers.set);
      final bytes = utf8.encode(jsonEncode(_body(history, model)));
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final raw = await utf8.decoder.bind(response).join();
        throw ApiException(
          '请求失败 (${response.statusCode})：${_errorMessage(raw)}',
        );
      }
      final decoder = SseDecoder();
      var received = false;
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        final payload = decoder.addLine(line);
        if (payload == null) continue;
        if (payload == '[DONE]') break;
        final piece = _textFromEvent(payload);
        if (piece.isNotEmpty) {
          received = true;
          yield piece;
        }
      }
      final tail = decoder.finish();
      if (tail != null && tail != '[DONE]') {
        final piece = _textFromEvent(tail);
        if (piece.isNotEmpty) {
          received = true;
          yield piece;
        }
      }
      if (!received) throw const ApiException('服务未返回文本，请检查模型和接口协议');
    } on SocketException catch (error) {
      throw ApiException('网络连接失败：${error.message}');
    } on HttpException {
      throw const ApiException('连接中断，请检查 API 地址或稍后重试');
    } on HandshakeException {
      throw const ApiException('HTTPS 证书验证失败');
    } on TimeoutException {
      throw const ApiException('请求超时，请检查网络和 API 地址');
    } finally {
      _client.close(force: true);
    }
  }

  String _textFromEvent(String payload) {
    final value = jsonDecode(payload);
    if (value is! Map<String, dynamic>) return '';
    if (value['type'] == 'error') {
      throw ApiException('服务错误：${_errorMessage(payload)}');
    }
    if (provider.protocol == ApiProtocol.anthropic) {
      if (value['type'] != 'content_block_delta') return '';
      final delta = value['delta'];
      return delta is Map && delta['type'] == 'text_delta'
          ? (delta['text'] as String? ?? '')
          : '';
    }
    if (value['error'] != null) {
      throw ApiException('服务错误：${_errorMessage(payload)}');
    }
    final choices = value['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final delta = choices.first['delta'];
    return delta is Map ? (delta['content'] as String? ?? '') : '';
  }

  Future<List<String>> fetchModels() async {
    try {
      final request = await _client
          .getUrl(Uri.parse('${provider.baseUrl}/models'))
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      _headers.forEach(request.headers.set);
      request.headers.set('accept', 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          '获取模型失败 (${response.statusCode})：${_errorMessage(raw)}',
        );
      }
      final json = jsonDecode(raw);
      final data = json is Map ? json['data'] : null;
      if (data is! List) throw const ApiException('此服务未提供兼容的模型列表');
      return data
          .whereType<Map>()
          .map((item) => item['id'])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
    } on TimeoutException {
      throw const ApiException('获取模型超时');
    } finally {
      _client.close(force: true);
    }
  }

  static String _errorMessage(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          return (error['message'] as String).substring(
            0,
            (error['message'] as String).length.clamp(0, 240),
          );
        }
        if (json['message'] is String) return json['message'] as String;
      }
    } catch (_) {
      /* Show a short server response below. */
    }
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 180 ? '${compact.substring(0, 180)}…' : compact;
  }
}
