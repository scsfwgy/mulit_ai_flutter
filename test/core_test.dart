import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api_client.dart';
import 'package:mulit_ai_flutter/data.dart';

void main() {
  test('SSE decoder joins data lines and ignores metadata', () {
    final decoder = SseDecoder();
    expect(decoder.addLine('event: content_block_delta'), isNull);
    expect(decoder.addLine('data: {"a":1,'), isNull);
    expect(decoder.addLine('data: "b":2}'), isNull);
    expect(decoder.addLine(''), '{"a":1,\n"b":2}');
    expect(decoder.finish(), isNull);
  });

  test('JSON import validates the full config and keeps the key separate', () {
    final value = ProviderConfig.fromImportJson('''{
      "name":"我的服务", "protocol":"openai_chat",
      "baseUrl":"https://api.example.com/v1/", "model":"demo-model",
      "apiKey":" secret "
    }''');
    expect(value.config.baseUrl, 'https://api.example.com/v1');
    expect(value.config.protocol, ApiProtocol.openAi);
    expect(value.key, 'secret');
    expect(value.config.toMap().containsKey('apiKey'), isFalse);
  });

  test('API key cannot be sent to an arbitrary cleartext endpoint', () {
    expect(
      () => validateBaseUrl('http://api.example.com/v1'),
      throwsFormatException,
    );
    expect(
      validateBaseUrl('http://10.0.2.2:8080/v1'),
      'http://10.0.2.2:8080/v1',
    );
  });

  test('presets have distinct IDs, valid API roots and local icons', () {
    expect(providerPresets.length, greaterThanOrEqualTo(15));
    expect(
      providerPresets.map((p) => p.id).toSet().length,
      providerPresets.length,
    );
    for (final preset in providerPresets) {
      expect(validateBaseUrl(preset.baseUrl), preset.baseUrl);
      expect(preset.iconAsset, startsWith('assets/provider_icons/'));
    }
  });

  test('global and model prompts are joined without empty sections', () {
    expect(composeSystemPrompt('全局', '模型'), '全局\n\n模型');
    expect(composeSystemPrompt(' 全局 ', ''), '全局');
    expect(composeSystemPrompt('', ' 模型 '), '模型');
  });

  test(
    'OpenAI-compatible adapter sends history and reads streamed text',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, dynamic>;
        seen.complete({
          'path': request.uri.path,
          'auth': request.headers.value('authorization'),
          'body': body,
        });
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"你好"}}]}\n\n'),
        );
        request.response.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"！"}}]}\n\n'),
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      try {
        final provider = ProviderConfig(
          id: 1,
          name: '测试',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'demo',
          protocol: ApiProtocol.openAi,
        );
        final history = [
          ChatMessage(
            id: 1,
            topicId: 1,
            role: 'user',
            content: '你好',
            createdAt: 1,
          ),
        ];
        final pieces = await ModelApiClient(
          provider,
          'test-key',
        ).streamReply(history, 'demo', systemPrompt: '全局\n\n模型').toList();
        expect(pieces.join(), '你好！');
        final request = await seen.future;
        expect(request['path'], '/v1/chat/completions');
        expect(request['auth'], 'Bearer test-key');
        expect((request['body'] as Map)['messages'], [
          {'role': 'system', 'content': '全局\n\n模型'},
          {'role': 'user', 'content': '你好'},
        ]);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('Claude adapter uses Messages headers and text deltas', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = Completer<Map<String, String?>>();
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      seen.complete({
        'path': request.uri.path,
        'key': request.headers.value('x-api-key'),
        'version': request.headers.value('anthropic-version'),
        'max_tokens': body['max_tokens'].toString(),
        'system': body['system'] as String?,
        'messages': jsonEncode(body['messages']),
      });
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write('event: content_block_delta\n');
      request.response.add(
        utf8.encode(
          'data: {"type":"content_block_delta",'
          '"delta":{"type":"text_delta","text":"Claude 回复"}}\n\n',
        ),
      );
      request.response.write('event: message_stop\n');
      request.response.write('data: {"type":"message_stop"}\n\n');
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 2,
        name: 'Claude',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'claude-sonnet-5',
        protocol: ApiProtocol.anthropic,
      );
      final pieces = await ModelApiClient(provider, 'test-key')
          .streamReply(
            [
              ChatMessage(
                id: 1,
                topicId: 1,
                role: 'user',
                content: '你好',
                createdAt: 1,
              ),
            ],
            'claude-sonnet-5',
            systemPrompt: '全局\n\n模型',
          )
          .toList();
      expect(pieces.join(), 'Claude 回复');
      final request = await seen.future;
      expect(request['path'], '/v1/messages');
      expect(request['key'], 'test-key');
      expect(request['version'], '2023-06-01');
      expect(request['max_tokens'], '4096');
      expect(request['system'], '全局\n\n模型');
      expect(request['messages'], '[{"role":"user","content":"你好"}]');
    } finally {
      await server.close(force: true);
    }
  });
}
