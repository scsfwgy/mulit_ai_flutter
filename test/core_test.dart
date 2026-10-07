import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/data.dart';

void main() {
  test('legacy provider names still resolve to their preset', () {
    // 旧配置没有 presetId，name 存的是当时语言下的译文（如中文的「GLM 智谱」），
    // 只拿当前的翻译 key 去比对会让这些配置失去预设图标与预设元数据。
    ProviderConfig config(String name, {String? baseUrl, String? presetId}) =>
        ProviderConfig(
          id: 1,
          name: name,
          baseUrl: baseUrl ?? 'https://open.bigmodel.cn/api/paas/v4',
          model: 'glm-4.5',
          protocol: ApiProtocol.openAi,
          presetId: presetId,
        );

    expect(presetForProvider(config('GLM 智谱'))?.id, 'glm');
    expect(presetForProvider(config('GLM (Zhipu)'))?.id, 'glm');
    expect(presetForProvider(config('i18n.glm_zhipu'))?.id, 'glm');
    expect(presetForProvider(config('我的中转服务')), isNull);

    // 地址不匹配时不按名称兜底。
    expect(
      presetForProvider(config('GLM 智谱', baseUrl: 'https://example.com/v1')),
      isNull,
    );

    // presetId 仍然优先，不受名称和地址影响。
    expect(
      presetForProvider(
        config('自定义名称', baseUrl: 'https://example.com/v1', presetId: 'qwen'),
      )?.id,
      'qwen',
    );
  });

  test('generated titles keep one short plain-text line', () {
    expect(initialTopicTitle('  第一行\n第二行  '), '第一行 第二行');
    expect(normalizeGeneratedTopicTitle('标题："人工智能入门"\n解释内容'), '人工智能入门');
    expect(normalizeGeneratedTopicTitle('  '), isNull);
    expect(
      normalizeGeneratedTopicTitle(List.filled(50, 'A').join()),
      '${List.filled(28, 'A').join()}…',
    );
  });

  test(
    'title request uses the selected model with a small token budget',
    () async {
      for (final protocol in ApiProtocol.values) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final seen = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          final body = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          seen.complete(body);
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          if (protocol == ApiProtocol.anthropic) {
            request.response.add(
              utf8.encode(
                'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"标题：人工智能入门"}}\n\n',
              ),
            );
          } else {
            request.response.add(
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"标题：人工智能入门"}}]}\n\n',
              ),
            );
          }
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        });
        try {
          final provider = ProviderConfig(
            id: 1,
            name: '测试',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'demo',
            protocol: protocol,
          );
          final title = await ModelApiClient(
            provider,
            'test-key',
          ).generateTopicTitle('chosen-model', '如何理解 AI？', '从数据和模式开始理解。');
          expect(title, '人工智能入门');
          final body = await seen.future;
          expect(body['model'], 'chosen-model');
          expect(body['max_tokens'], 64);
          expect(body['stream'], isTrue);
          expect(
            (body['messages'] as List).last['content'],
            contains('如何理解 AI？'),
          );
          if (protocol == ApiProtocol.anthropic) {
            expect(body['system'], contains('简短标题'));
          } else {
            expect((body['messages'] as List).first['role'], 'system');
          }
        } finally {
          await server.close(force: true);
        }
      }
    },
  );

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

  test('QR import accepts complete JSON and rejects missing key or HTTP', () {
    final value = ProviderConfig.fromQrCode('''{
      "name":"扫码服务", "protocol":"openai_chat",
      "baseUrl":"https://api.example.com/v1", "model":"demo",
      "apiKey":" qr-test-key "
    }''');
    expect(value.config.name, '扫码服务');
    expect(value.key, 'qr-test-key');
    expect(value.config.toMap().containsKey('apiKey'), isFalse);
    expect(
      () => ProviderConfig.fromQrCode('''{
        "name":"扫码服务", "protocol":"openai_chat",
        "baseUrl":"https://api.example.com/v1", "model":"demo",
        "apiKey":""
      }'''),
      throwsFormatException,
    );
    expect(
      () => ProviderConfig.fromQrCode('''{
        "name":"扫码服务", "protocol":"openai_chat",
        "baseUrl":"http://api.example.com/v1", "model":"demo",
        "apiKey":"qr-test-key"
      }'''),
      throwsFormatException,
    );
  });

  test(
    'key-only QR accepts a string and rejects JSON or control characters',
    () {
      expect(validateScannedApiKey('  test-key  '), 'test-key');
      expect(() => validateScannedApiKey('  '), throwsFormatException);
      expect(() => validateScannedApiKey('line\nbreak'), throwsFormatException);
      expect(
        () => validateScannedApiKey('{"apiKey":"test-key"}'),
        throwsFormatException,
      );
    },
  );

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

  test('model list uses the selected service URL and API key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = Completer<Map<String, String?>>();
    server.listen((request) async {
      seen.complete({
        'path': request.uri.path,
        'auth': request.headers.value('authorization'),
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write('''{
        "data": [{"id":"model-b"}, {"id":"model-a"},
                 {"id":"model-b"}, {"name":"missing-id"}]
      }''');
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 1,
        name: '测试',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'default-model',
        protocol: ApiProtocol.openAi,
      );
      final models = await ModelApiClient(provider, 'test-key').fetchModels();
      expect(models, ['model-a', 'model-b']);
      expect(await seen.future, {
        'path': '/v1/models',
        'auth': 'Bearer test-key',
      });
    } finally {
      await server.close(force: true);
    }
  });

  test('cached models retain IDs and only match the same API endpoint', () {
    const provider = ProviderConfig(
      id: 7,
      name: '聚合服务',
      baseUrl: 'https://example.com/v1',
      model: 'default',
      protocol: ApiProtocol.openAi,
    );
    final cache = CachedModelList(
      baseUrl: provider.baseUrl,
      protocol: provider.protocol,
      models: const ['claude-opus-4-6', 'MiniMax-M3'],
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final restored = CachedModelList.tryParse(cache.toJson());
    expect(restored?.models, cache.models);
    expect(restored?.fetchedAt, cache.fetchedAt);
    expect(restored?.matches(provider), isTrue);
    expect(
      restored?.matches(provider.copyWith(baseUrl: 'https://new.example.com')),
      isFalse,
    );
    expect(
      restored?.matches(provider.copyWith(protocol: ApiProtocol.anthropic)),
      isFalse,
    );
    expect(CachedModelList.tryParse('{bad json'), isNull);
  });

  test('unauthorized chat response is identified as a key error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 401;
      request.response.write('{"error":{"message":"invalid key"}}');
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
      await expectLater(
        ModelApiClient(provider, 'test-key').streamReply([], 'demo').toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.auth,
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('server errors never expose the configured API key', () async {
    const secret = 'sk-secret-value-123';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'error': {'message': 'Rejected $secret'},
        }),
      );
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
      for (final operation in <Future<Object?> Function()>[
        () => ModelApiClient(provider, secret).fetchModels(),
        () => ModelApiClient(provider, secret).streamReply([], 'demo').toList(),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              allOf(contains('[已隐藏]'), isNot(contains(secret))),
            ),
          ),
        );
      }
    } finally {
      await server.close(force: true);
    }
  });

  test('malformed model list does not echo the server response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write('invalid-json-sk-secret-value-123');
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
      await expectLater(
        ModelApiClient(provider, 'sk-secret-value-123').fetchModels(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            isNot(contains('sk-secret-value-123')),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('streamed service errors also hide the API key', () async {
    const secret = 'sk-stream-secret-123';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: ${jsonEncode({
          'error': {'message': 'Rejected $secret'},
        })}\n\n',
      );
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
      await expectLater(
        ModelApiClient(provider, secret).streamReply([], 'demo').toList(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            allOf(contains('[已隐藏]'), isNot(contains(secret))),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
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
            providerId: 7,
            providerName: '旧服务',
          ),
          const ChatMessage(
            id: 2,
            topicId: 1,
            role: 'assistant',
            content: '你好，我是旧服务',
            createdAt: 2,
            providerId: 7,
            providerName: '旧服务',
          ),
          const ChatMessage(
            id: 3,
            topicId: 1,
            role: 'user',
            content: '接着说',
            createdAt: 3,
            providerId: 1,
            providerName: '测试',
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
          {'role': 'assistant', 'content': '你好，我是旧服务'},
          {'role': 'user', 'content': '接着说'},
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
