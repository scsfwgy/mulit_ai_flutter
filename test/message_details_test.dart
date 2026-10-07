import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/data.dart';

void main() {
  test('message metadata reads new rows and leaves legacy values unknown', () {
    final original = {
      'id': 1,
      'topic_id': 2,
      'role': 'assistant',
      'content': 'Hello',
      'created_at': 3,
    };
    final old = ChatMessage.fromMap(original);
    expect(old.modelId, isNull);
    expect(old.providerName, isNull);
    expect(old.firstTokenMs, isNull);
    expect(old.inputTokens, isNull);

    final recent = ChatMessage.fromMap({
      ...original,
      'model_id': 'provider/model',
      'provider_id': 7,
      'provider_name': 'OpenAI',
      'provider_preset_id': 'openai',
      'first_token_ms': 620,
      'total_ms': 1420,
      'input_tokens': 38,
      'output_tokens': 12,
    });
    expect(recent.modelId, 'provider/model');
    expect(recent.providerId, 7);
    expect(recent.providerName, 'OpenAI');
    expect(recent.providerPresetId, 'openai');
    expect(recent.firstTokenMs, 620);
    expect(recent.totalMs, 1420);
    expect(recent.inputTokens, 38);
    expect(recent.outputTokens, 12);
  });

  test(
    'OpenAI compatible stream requests and reads actual token usage',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestBody = Completer<Map<String, dynamic>>();
      server.listen((request) async {
        requestBody.complete(
          jsonDecode(await utf8.decoder.bind(request).join()),
        );
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"Hello"}}],"usage":null}\n\n',
        );
        request.response.write(
          'data: {"choices":[],"usage":{"prompt_tokens":38,"completion_tokens":12}}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      try {
        final provider = ProviderConfig(
          id: 1,
          name: 'test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'demo',
          protocol: ApiProtocol.openAi,
        );
        ReplyUsage? usage;
        final result = await ModelApiClient(
          provider,
          'test-key',
        ).streamReply([], 'demo', onUsage: (value) => usage = value).join();
        expect(result, 'Hello');
        expect(usage?.inputTokens, 38);
        expect(usage?.outputTokens, 12);
        expect((await requestBody.future)['stream_options'], {
          'include_usage': true,
        });
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('Claude stream combines cache tokens and final output usage', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"type":"message_start","message":{"usage":{"input_tokens":8,"cache_creation_input_tokens":3,"cache_read_input_tokens":10,"output_tokens":1}}}\n\n',
      );
      request.response.write(
        'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}\n\n',
      );
      request.response.write(
        'data: {"type":"message_delta","usage":{"output_tokens":6}}\n\n',
      );
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 1,
        name: 'test',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'demo',
        protocol: ApiProtocol.anthropic,
      );
      ReplyUsage? usage;
      final result = await ModelApiClient(provider, 'test-key')
          .streamReply(
            [],
            'demo',
            onUsage: (value) =>
                usage = (usage ?? const ReplyUsage()).merge(value),
          )
          .join();
      expect(result, 'Hi');
      expect(usage?.inputTokens, 21);
      expect(usage?.outputTokens, 6);
    } finally {
      await server.close(force: true);
    }
  });

  test('unsupported stream usage option falls back once', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <Map<String, dynamic>>[];
    server.listen((request) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      if (bodies.length == 1) {
        request.response.statusCode = 400;
        request.response.write(
          '{"error":{"message":"Unknown stream_options"}}',
        );
      } else {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"works"}}]}\n\n',
        );
      }
      await request.response.close();
    });
    try {
      final provider = ProviderConfig(
        id: 1,
        name: 'test',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'demo',
        protocol: ApiProtocol.openAi,
      );
      final result = await ModelApiClient(
        provider,
        'test-key',
      ).streamReply([], 'demo', onUsage: (_) {}).join();
      expect(result, 'works');
      expect(bodies.length, 2);
      expect(bodies.first['stream_options'], isNotNull);
      expect(bodies.last['stream_options'], isNull);
    } finally {
      await server.close(force: true);
    }
  });
}
