import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/chat/memory_profile.dart';
import 'package:mulit_ai_flutter/core/data.dart';

ChatMessage _message(int id, String role, String content) => ChatMessage(
  id: id,
  topicId: 1,
  role: role,
  content: content,
  createdAt: id,
);

void main() {
  test('a chat uses memory only when the master switch and a link agree', () {
    expect(
      topicUsesMemory(
        enabled: false,
        inGlobalPrompt: true,
        topicOverride: true,
      ),
      isFalse,
    );
    expect(topicUsesMemory(enabled: true, inGlobalPrompt: true), isTrue);
    expect(topicUsesMemory(enabled: true, inGlobalPrompt: false), isFalse);
    expect(
      topicUsesMemory(
        enabled: true,
        inGlobalPrompt: false,
        topicOverride: true,
      ),
      isTrue,
    );
    expect(
      topicUsesMemory(
        enabled: true,
        inGlobalPrompt: true,
        topicOverride: false,
      ),
      isFalse,
    );
  });

  test(
    'memory merge keeps only new complete turns and a capped transcript',
    () {
      final first = [
        _message(1, 'user', '我喜欢喝茶'),
        _message(2, 'assistant', '记住了'),
        _message(3, 'user', '这句还没有回复'),
      ];
      final budget = memoryTranscriptTokenBudget(8192);
      final open = buildMemoryMerge(
        messages: first,
        cursorMessageId: 0,
        transcriptTokenBudget: budget,
      );
      expect(open, isNotNull);
      expect(open!.cursorMessageId, 2);
      expect(open.transcript, contains('我喜欢喝茶'));
      expect(open.transcript, isNot(contains('这句还没有回复')));

      final continued = buildMemoryMerge(
        messages: [
          ...first,
          _message(4, 'assistant', '好的'),
          _message(5, 'user', '请叫我林'),
          _message(6, 'assistant', '收到'),
        ],
        cursorMessageId: open.cursorMessageId,
        transcriptTokenBudget: budget,
      );
      expect(continued!.cursorMessageId, 6);
      expect(continued.transcript, isNot(contains('我喜欢喝茶')));
      expect(continued.transcript, contains('请叫我林'));

      final huge = '字' * 5000;
      final clipped = buildMemoryMerge(
        messages: [
          _message(1, 'user', huge),
          _message(2, 'assistant', huge),
          _message(3, 'user', '第二条'),
          _message(4, 'assistant', '第二条回复'),
        ],
        cursorMessageId: 0,
        transcriptTokenBudget: 300,
      );
      expect(clipped!.cursorMessageId, 2);
      expect(
        ChatContext.estimateTokens(clipped.transcript),
        lessThanOrEqualTo(budget),
      );
      expect(clipped.transcript, isNot(contains('第二条')));
      final packed = buildMemoryMerge(
        messages: [
          for (var i = 0; i < 8; i++)
            _message(i + 1, i.isEven ? 'user' : 'assistant', '句' * 700),
        ],
        cursorMessageId: 0,
        transcriptTokenBudget: budget,
      );
      expect(packed, isNotNull);
      expect(
        ChatContext.estimateTokens(packed!.transcript),
        lessThanOrEqualTo(budget),
      );
      expect(
        () => ChatContext.select(
          [
            {
              'role': 'user',
              'content': memoryMergeUserContent(
                '字' * memoryProfileMaxChars,
                packed.transcript,
              ),
            },
          ],
          systemPrompt: memoryMergeInstruction,
          windowTokens: 8192,
          outputTokens: memoryMergeMaxTokens,
        ),
        returnsNormally,
      );
      expect(
        buildMemoryMerge(
          messages: first,
          cursorMessageId: 2,
          transcriptTokenBudget: budget,
        ),
        isNull,
      );
      expect(_message(1, 'user', '字' * 900).content.runes.length, 900);
      final longTurn = buildMemoryMerge(
        messages: [
          _message(1, 'user', '字' * 900),
          _message(2, 'assistant', '好'),
        ],
        cursorMessageId: 0,
        transcriptTokenBudget: budget,
      );
      expect(longTurn!.transcript, contains('用户：${'字' * memoryTurnClipChars}'));
      expect(longTurn.transcript, isNot(contains('字' * 701)));
    },
  );

  test('empty model memory text keeps the caller on the previous profile', () {
    expect(normalizeMemoryProfile('  '), isNull);
    expect(normalizeMemoryProfile('（空）'), isNull);
    expect(normalizeMemoryProfile('用户资料：喜欢红茶'), '喜欢红茶');
    expect(normalizeMemoryProfile('资料: tea'), 'tea');
    expect(
      normalizeMemoryProfile('字' * 900)!.runes.length,
      memoryProfileMaxChars,
    );
  });

  test(
    'memory merge sends the profile and new turns with a short output cap',
    () async {
      for (final protocol in ApiProtocol.values) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final seen = Completer<Map<String, dynamic>>();
        server.listen((request) async {
          seen.complete(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          if (protocol == ApiProtocol.anthropic) {
            request.response.add(
              utf8.encode(
                'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"用户资料：喜欢喝茶"}}\n\n',
              ),
            );
          } else {
            request.response.add(
              utf8.encode(
                'data: {"choices":[{"delta":{"content":"用户资料：喜欢喝茶"}}]}\n\n',
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
          final updated = await ModelApiClient(
            provider,
            'test-key',
          ).mergeMemoryProfile('chosen-model', '旧资料', '用户：我喜欢喝茶');
          expect(updated, '喜欢喝茶');
          final body = await seen.future;
          expect(body['model'], 'chosen-model');
          expect(body['max_tokens'], memoryMergeMaxTokens);
          final encoded = jsonEncode(body);
          expect(encoded, contains('旧资料'));
          expect(encoded, contains('我喜欢喝茶'));
          expect(encoded, contains('不要写入指令'));
        } finally {
          await server.close(force: true);
        }
      }
    },
  );
}
