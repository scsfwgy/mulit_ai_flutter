import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_context.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/data.dart';

void main() {
  test('context estimate reserves the actual adaptive output budget', () {
    final first = AgentContext.prepare(
      protocol: ApiProtocol.openAi,
      model: 'test',
      prompt: '',
      messages: [
        {'role': 'user', 'content': 'test'},
      ],
      tools: [],
      windowTokens: 1048576,
      outputTokens: 8192,
    );
    final second = AgentContext.prepare(
      protocol: ApiProtocol.openAi,
      model: 'test',
      prompt: '',
      messages: [
        {'role': 'user', 'content': 'test'},
      ],
      tools: [],
      windowTokens: 1048576,
      outputTokens: 16384,
    );
    expect(second.tokens - first.tokens, inInclusiveRange(8192, 8200));
  });

  for (final protocol in ApiProtocol.values) {
    test(
      '$protocol compacts request only and preserves tool relationships',
      () {
        final messages = <Map<String, dynamic>>[
          {'role': 'user', 'content': 'Research'},
          if (protocol == ApiProtocol.openAi)
            {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {
                    'name': 'read_webpage',
                    'arguments': '{"url":"https://example.com"}',
                  },
                },
              ],
            }
          else
            {
              'role': 'assistant',
              'content': [
                {
                  'type': 'thinking',
                  'thinking': 'plan',
                  'signature': 'signature',
                },
                {
                  'type': 'tool_use',
                  'id': 'c1',
                  'name': 'read_webpage',
                  'input': {'url': 'https://example.com'},
                },
              ],
            },
        ];
        appendModelToolResult(
          messages,
          protocol,
          const ModelToolCall('c1', 'read_webpage', {}),
          jsonEncode({'text': '长正文' * 10000, 'url': 'https://example.com'}),
        );
        final original = jsonEncode(messages);
        final prepared = AgentContext.prepare(
          protocol: protocol,
          model: 'test',
          prompt: 'System',
          messages: messages,
          tools: [],
          windowTokens: 8192,
        );
        expect(prepared.tokens, lessThanOrEqualTo(8192));
        expect(prepared.compacted, true);
        expect(jsonEncode(messages), original);
        expect(prepared.messages[1], messages[1]);
        final result = protocol == ApiProtocol.openAi
            ? prepared.messages.last
            : (prepared.messages.last['content'] as List).last as Map;
        expect(
          result[protocol == ApiProtocol.openAi
              ? 'tool_call_id'
              : 'tool_use_id'],
          'c1',
        );
        expect(jsonDecode(result['content'])['url'], 'https://example.com');
      },
    );
  }

  test(
    'drops complete older turns and never splits the current tool chain',
    () {
      final prepared = AgentContext.prepare(
        protocol: ApiProtocol.openAi,
        model: 'test',
        prompt: '',
        tools: [],
        windowTokens: 8192,
        messages: [
          {'role': 'user', 'content': 'old ' * 20000},
          {'role': 'assistant', 'content': 'old reply'},
          {'role': 'user', 'content': 'current'},
          {'role': 'assistant', 'content': 'current reply'},
        ],
      );
      expect(prepared.messages.map((m) => m['content']), [
        'current',
        'current reply',
      ]);
      expect(prepared.compacted, true);
    },
  );

  test(
    'mandatory oversized input fails instead of dropping current message',
    () {
      expect(
        () => AgentContext.prepare(
          protocol: ApiProtocol.openAi,
          model: 'test',
          prompt: '',
          tools: [],
          messages: [
            {'role': 'user', 'content': 'x' * 100000},
          ],
          windowTokens: 8192,
        ),
        throwsA(isA<AgentContextException>()),
      );
    },
  );

  test(
    'binary attachments use fixed estimate without modifying wire payload',
    () {
      final payload = 'data:image/png;base64,${'a' * 500000}';
      final message = <String, dynamic>{
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'url': payload},
          },
          {'type': 'text', 'text': 'Describe'},
        ],
      };
      final prepared = AgentContext.prepare(
        protocol: ApiProtocol.openAi,
        model: 'test',
        prompt: '',
        tools: [],
        messages: [message],
        windowTokens: 8192,
      );
      expect(prepared.tokens, lessThan(8192));
      expect(prepared.messages.single, message);
      expect(prepared.compacted, false);
    },
  );
}
