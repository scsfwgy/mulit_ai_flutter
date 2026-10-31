import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/agent/web_reader.dart';

Map<String, dynamic> toolResponse(
  ApiProtocol protocol, {
  String reason = '',
  String arguments = '{"query":"test"}',
}) => protocol == ApiProtocol.openAi
    ? {
        'choices': [
          {
            'finish_reason': reason.isEmpty ? 'tool_calls' : reason,
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call1',
                  'type': 'function',
                  'function': {'name': 'search_web', 'arguments': arguments},
                },
              ],
            },
          },
        ],
        'usage': {'prompt_tokens': 20, 'completion_tokens': 10},
      }
    : {
        'stop_reason': reason.isEmpty ? 'tool_use' : reason,
        'content': [
          {
            'type': 'tool_use',
            'id': 'call1',
            'name': 'search_web',
            'input': jsonDecode(arguments),
          },
        ],
        'usage': {'input_tokens': 20, 'output_tokens': 10},
      };

void main() {
  test('empty choices is a diagnosable invalid response', () {
    expect(
      () => ModelToolTurn.parse({'choices': []}, ApiProtocol.openAi),
      throwsA(
        isA<ModelTurnException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('Claude accepts a complete stop_sequence text answer', () {
    final turn = ModelToolTurn.parse({
      'stop_reason': 'stop_sequence',
      'content': [
        {'type': 'text', 'text': 'Answer'},
      ],
    }, ApiProtocol.anthropic);
    expect(turn.text, 'Answer');
    expect(turn.calls, isEmpty);
  });

  test(
    'DeepSeek restores available reasoning and quotes old plain-chat replies',
    () async {
      final client = ModelApiClient(
        ProviderConfig(
          id: 1,
          name: 'Test',
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-flash',
          protocol: ApiProtocol.openAi,
        ),
        'unused',
      );
      final history = [
        const ChatMessage(
          id: 1,
          topicId: 1,
          role: 'user',
          content: 'Earlier question',
          createdAt: 1,
        ),
        const ChatMessage(
          id: 2,
          topicId: 1,
          role: 'assistant',
          content: 'Earlier answer',
          createdAt: 2,
        ),
        const ChatMessage(
          id: 3,
          topicId: 1,
          role: 'user',
          content: 'Next question',
          createdAt: 3,
        ),
      ];
      try {
        final quoted = await client.toolHistory(
          history,
          'deepseek-flash',
          '',
          32768,
        );
        expect(quoted.length, 2);
        expect(quoted.first['role'], 'user');
        expect('${quoted.first['content']}', contains('Earlier answer'));
        expect(history[1].role, 'assistant');
        final native = await client.toolHistory(
          history,
          'deepseek-flash',
          '',
          32768,
          assistantReplay: {
            2: {'reasoning_content': 'Native state'},
          },
        );
        expect(native.length, 3);
        expect(native[1]['reasoning_content'], 'Native state');
      } finally {
        client.cancel();
      }
    },
  );

  test(
    'Claude preserves signed thinking when replaying a prior task reply',
    () async {
      final client = ModelApiClient(
        ProviderConfig(
          id: 1,
          name: 'Test',
          baseUrl: 'https://example.com',
          model: 'claude',
          protocol: ApiProtocol.anthropic,
        ),
        'unused',
      );
      try {
        final wire = await client.toolHistory(
          [
            const ChatMessage(
              id: 1,
              topicId: 1,
              role: 'user',
              content: 'Question',
              createdAt: 1,
            ),
            const ChatMessage(
              id: 2,
              topicId: 1,
              role: 'assistant',
              content: 'Answer',
              createdAt: 2,
            ),
            const ChatMessage(
              id: 3,
              topicId: 1,
              role: 'user',
              content: 'Continue',
              createdAt: 3,
            ),
          ],
          'claude',
          '',
          32768,
          assistantReplay: {
            2: {
              'content': [
                {'type': 'thinking', 'thinking': 'plan', 'signature': 'signed'},
              ],
            },
          },
        );
        expect(wire[1]['content'][0]['signature'], 'signed');
        expect(wire[1]['content'][1]['text'], 'Answer');
      } finally {
        client.cancel();
      }
    },
  );

  test(
    'OpenAI adapts only an explicit completion-token parameter rejection',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var count = 0;
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (count++ == 0) {
          expect(body['max_tokens'], 4096);
          request.response.statusCode = 400;
          request.response.write(
            '{"error":{"message":"Unsupported max_tokens; use max_completion_tokens instead"}}',
          );
        } else {
          expect(body.containsKey('max_tokens'), false);
          expect(body['max_completion_tokens'], 4096);
          request.response.write(jsonEncode(toolResponse(ApiProtocol.openAi)));
        }
        await request.response.close();
      });
      final client = ModelApiClient(
        ProviderConfig(
          id: 1,
          name: 'Test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'test',
          protocol: ApiProtocol.openAi,
        ),
        'test-key',
      );
      try {
        await client.toolTurn(
          model: 'test',
          systemPrompt: '',
          messages: [
            {'role': 'user', 'content': 'test'},
          ],
          tools: [],
        );
        expect(count, 2);
      } finally {
        client.cancel();
        await server.close(force: true);
      }
    },
  );
  test('Claude returns parallel tool results in one user content block', () {
    final messages = <Map<String, dynamic>>[
      {'role': 'assistant', 'content': []},
    ];
    appendModelToolResult(
      messages,
      ApiProtocol.anthropic,
      const ModelToolCall('a', 'search_web', {}),
      'first',
    );
    appendModelToolResult(
      messages,
      ApiProtocol.anthropic,
      const ModelToolCall('b', 'read_webpage', {}),
      'second',
    );
    expect(messages.length, 2);
    expect((messages.last['content'] as List).map((b) => b['tool_use_id']), [
      'a',
      'b',
    ]);
  });
  for (final protocol in ApiProtocol.values) {
    test(
      '${protocol.name} accepts tool-only turns and preserves result IDs',
      () {
        final turn = ModelToolTurn.parse(toolResponse(protocol), protocol);
        expect(turn.text, '');
        expect(turn.calls.single.arguments, {'query': 'test'});
        expect(turn.inputTokens, 20);
        final result = modelToolResult(protocol, turn.calls.single, 'ok');
        if (protocol == ApiProtocol.openAi) {
          expect(result['tool_call_id'], 'call1');
        } else {
          expect((result['content'] as List).single['tool_use_id'], 'call1');
        }
      },
    );

    test('${protocol.name} rejects truncated turns before executing', () {
      expect(
        () => ModelToolTurn.parse(
          toolResponse(
            protocol,
            reason: protocol == ApiProtocol.openAi ? 'length' : 'max_tokens',
          ),
          protocol,
        ),
        throwsFormatException,
      );
    });

    test(
      '${protocol.name} sends native schemas and complete tool messages',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        Map<String, dynamic>? seen;
        server.listen((request) async {
          seen = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(toolResponse(protocol)));
          await request.response.close();
        });
        final client = ModelApiClient(
          ProviderConfig(
            id: 1,
            name: 'Test',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'demo',
            protocol: protocol,
          ),
          'not-a-real-key',
        );
        try {
          final turn = await client.toolTurn(
            model: 'chosen',
            systemPrompt: 'task prompt',
            messages: [
              {'role': 'user', 'content': 'research'},
            ],
            tools: [
              {
                'name': 'search_web',
                'description': 'Search',
                'parameters': {'type': 'object'},
              },
            ],
          );
          expect(turn.calls.single.id, 'call1');
          expect(seen!['stream'], false);
          expect(seen!['model'], 'chosen');
          expect(seen!['max_tokens'], 4096);
          if (protocol == ApiProtocol.openAi) {
            expect(
              seen!['tools'][0]['function']['parameters']['type'],
              'object',
            );
          } else {
            expect(seen!['tools'][0]['input_schema']['type'], 'object');
            expect(seen!['system'], 'task prompt');
          }
        } finally {
          client.cancel();
          await server.close(force: true);
        }
      },
    );
  }

  test('malformed arguments become a paired tool error, duplicate IDs are rejected', () {
    final invalid = ModelToolTurn.parse(
      toolResponse(ApiProtocol.openAi, arguments: '{'),
      ApiProtocol.openAi,
    );
    expect(invalid.calls.single.argumentError, true);
    expect(
      ModelToolCall.fromJson(invalid.calls.single.toJson()).argumentError,
      true,
    );
    final json = toolResponse(ApiProtocol.openAi);
    final calls = json['choices'][0]['message']['tool_calls'] as List;
    calls.add(calls.single);
    expect(
      () => ModelToolTurn.parse(json, ApiProtocol.openAi),
      throwsFormatException,
    );
  });

  test(
    'truncation keeps stop reason and reported usage without accepting calls',
    () {
      expect(
        () => ModelToolTurn.parse(
          toolResponse(ApiProtocol.openAi, reason: 'length'),
          ApiProtocol.openAi,
        ),
        throwsA(
          isA<ModelTurnException>()
              .having((e) => e.code, 'code', 'output_limit')
              .having((e) => e.finishReason, 'reason', 'length')
              .having((e) => e.outputTokens, 'usage', 10),
        ),
      );
    },
  );

  test('complete stop turns with tool calls and text content arrays are compatible', () {
    final json = toolResponse(ApiProtocol.openAi, reason: 'stop');
    json['choices'][0]['message']['content'] = [
      {'type': 'text', 'text': 'Checking'},
    ];
    final turn = ModelToolTurn.parse(json, ApiProtocol.openAi);
    expect(turn.calls.length, 1);
    expect(turn.text, 'Checking');
  });

  test(
    'larger parallel batches do not hit an arbitrary six-call parser limit',
    () {
      final json = toolResponse(ApiProtocol.openAi);
      final original =
          (json['choices'][0]['message']['tool_calls'] as List).single as Map;
      json['choices'][0]['message']['tool_calls'] = [
        for (var i = 0; i < 8; i++) {...original, 'id': 'call$i'},
      ];
      expect(ModelToolTurn.parse(json, ApiProtocol.openAi).calls.length, 8);
    },
  );

  test(
    'both protocols disable tools for wrap-up while retaining native schemas',
    () {
      for (final protocol in ApiProtocol.values) {
        final body = modelToolBody(
          protocol,
          'model',
          'prompt',
          [],
          [
            {
              'name': 'search_web',
              'parameters': {'type': 'object'},
            },
          ],
          outputTokens: 16384,
          allowTools: false,
        );
        expect(body['max_tokens'], 16384);
        expect(
          body['tool_choice'],
          protocol == ApiProtocol.openAi ? 'none' : {'type': 'none'},
        );
        expect(body['tools'], isNotEmpty);
      }
    },
  );

  test(
    'provider reasoning fields and cache usage survive tool continuation',
    () {
      final openai = toolResponse(ApiProtocol.openAi);
      openai['choices'][0]['message']['reasoning_content'] =
          'provider-required state';
      expect(
        ModelToolTurn.parse(
          openai,
          ApiProtocol.openAi,
        ).message['reasoning_content'],
        'provider-required state',
      );
      final claude = toolResponse(ApiProtocol.anthropic);
      claude['usage']['cache_creation_input_tokens'] = 2;
      claude['usage']['cache_read_input_tokens'] = 3;
      expect(
        ModelToolTurn.parse(claude, ApiProtocol.anthropic).inputTokens,
        25,
      );
    },
  );

  test(
    'web reader excludes private, mapped, link-local and transition addresses',
    () {
      for (final address in [
        '0.0.0.0',
        '127.0.0.1',
        '10.0.0.1',
        '192.168.0.1',
        '172.16.1.1',
        '169.254.169.254',
        '100.64.1.1',
        '224.0.0.1',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fe80::1',
        '2002:7f00:1::',
        '2001:db8::1',
      ]) {
        expect(
          isPublicAgentAddress(InternetAddress(address)),
          isFalse,
          reason: address,
        );
      }
      expect(isPublicAgentAddress(InternetAddress('8.8.8.8')), isTrue);
      expect(
        isPublicAgentAddress(InternetAddress('2606:4700:4700::1111')),
        isTrue,
      );
      for (final url in [
        'file:///tmp/test',
        'http://example.com',
        'https://127.0.0.1',
        'https://example.com:8443',
        'https://user:password@example.com',
        'https://localhost',
      ]) {
        expect(() => publicAgentUri(url), throwsFormatException);
      }
      expect(publicAgentUri('https://example.com/article').host, 'example.com');
    },
  );

  test(
    'HTML reader decodes entities and excludes executable/navigation content',
    () {
      final text = extractAgentWebText(
        '<html><body><nav>menu</nav><script>steal()</script><p>Fish &amp; chips</p><p>Next</p></body></html>',
      );
      expect(text, contains('Fish & chips'));
      expect(text, contains('Next'));
      expect(text, isNot(contains('steal')));
      expect(text, isNot(contains('menu')));
    },
  );
}
