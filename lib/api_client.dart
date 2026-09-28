import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'data.dart';

enum ApiErrorKind { other, network, auth, model }

class ApiException implements Exception {
  const ApiException(this.message, {this.kind = ApiErrorKind.other});
  final String message;
  final ApiErrorKind kind;
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

  Map<String, Object?> _body(
    List<ChatMessage> history,
    String model,
    String systemPrompt,
    int? maxTokens,
  ) {
    final messages = history
        .map((message) => {'role': message.role, 'content': message.content})
        .toList();
    if (provider.protocol == ApiProtocol.anthropic) {
      return {
        'model': model,
        'max_tokens': maxTokens ?? 4096,
        'stream': true,
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
        'messages': messages,
      };
    }
    return {
      'model': model,
      'stream': true,
      'max_tokens': ?maxTokens,
      'messages': [
        if (systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
    };
  }

  Stream<String> streamReply(
    List<ChatMessage> history,
    String model, {
    String systemPrompt = '',
    int? maxTokens,
  }) async* {
    try {
      final request = await _client
          .postUrl(_chatUri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      _headers.forEach(request.headers.set);
      final bytes = utf8.encode(
        jsonEncode(_body(history, model, systemPrompt, maxTokens)),
      );
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final raw = await _readErrorBody(response);
        throw ApiException(
          '请求失败 (${response.statusCode})：${_errorMessage(raw)}',
          kind: switch (response.statusCode) {
            401 || 403 => ApiErrorKind.auth,
            _ => ApiErrorKind.other,
          },
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
      if (!received) {
        throw const ApiException(
          '服务未返回文本，请检查模型和接口协议',
          kind: ApiErrorKind.model,
        );
      }
    } on FormatException {
      throw const ApiException('服务返回的数据格式不正确，请检查接口协议');
    } on SocketException catch (error) {
      throw ApiException('网络连接失败：${error.message}', kind: ApiErrorKind.network);
    } on HttpException {
      throw const ApiException(
        '连接中断，请检查 API 地址或稍后重试',
        kind: ApiErrorKind.network,
      );
    } on HandshakeException {
      throw const ApiException('HTTPS 证书验证失败');
    } on TimeoutException {
      throw const ApiException(
        '请求超时，请检查网络和 API 地址',
        kind: ApiErrorKind.network,
      );
    } finally {
      _client.close(force: true);
    }
  }

  Future<String?> generateTopicTitle(
    String model,
    String userMessage,
    String assistantMessage,
  ) async {
    String clip(String text) =>
        text.length > 700 ? text.substring(0, 700) : text;
    final summaryInput =
        '用户：${clip(userMessage)}\n助手：${clip(assistantMessage)}';
    final prompt = ChatMessage(
      id: 0,
      topicId: 0,
      role: 'user',
      content: summaryInput,
      createdAt: 0,
    );
    final result = StringBuffer();
    await for (final chunk in streamReply(
      [prompt],
      model,
      systemPrompt: '根据这段对话拟一个简短标题，使用对话的语言。只输出标题，不加引号、序号或解释。',
      maxTokens: 64,
    )) {
      result.write(chunk);
      if (result.length >= 120) break;
    }
    return normalizeGeneratedTopicTitle(result.toString());
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final raw = await _readErrorBody(response);
        throw ApiException(
          '获取模型失败 (${response.statusCode})：${_errorMessage(raw)}',
        );
      }
      final raw = await utf8.decoder.bind(response).join();
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
    } on FormatException {
      throw const ApiException('模型列表格式不正确，请手动输入模型 ID');
    } on TimeoutException {
      throw const ApiException('获取模型超时');
    } finally {
      _client.close(force: true);
    }
  }

  Future<String> _readErrorBody(HttpClientResponse response) async {
    const maxBytes = 16 * 1024;
    final bytes = <int>[];
    await for (final chunk in response) {
      final remaining = maxBytes - bytes.length;
      if (remaining <= 0) break;
      bytes.addAll(chunk.take(remaining));
      if (bytes.length == maxBytes) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _errorMessage(String raw) {
    String message = raw;
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          message = error['message'] as String;
        } else if (json['message'] is String) {
          message = json['message'] as String;
        }
      }
    } catch (_) {
      // Some compatible APIs return plain text errors.
    }
    for (final value in {apiKey, Uri.encodeComponent(apiKey)}) {
      if (value.isNotEmpty) message = message.replaceAll(value, '[已隐藏]');
    }
    final compact = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 240 ? '${compact.substring(0, 240)}…' : compact;
  }
}
