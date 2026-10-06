import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat_context.dart';

Map<String, String> message(String role, String content) => {
  'role': role,
  'content': content,
};

void main() {
  test(
    'budget keeps recent complete turns without altering stored history',
    () {
      final history = [
        message('user', 'first question'),
        message('assistant', 'x' * 3000),
        message('user', 'second question'),
        message('assistant', 'second answer'),
        message('user', 'latest question'),
      ];
      final selected = ChatContext.select(
        history,
        systemPrompt: 'system',
        windowTokens: 900,
        outputTokens: 64,
      );
      expect(selected, history.sublist(2));
      expect(selected.first['role'], 'user');
      expect(selected.last['content'], 'latest question');
      expect(history.length, 5);
      expect(history[1]['content']!.length, 3000);
    },
  );

  test('keeps a contiguous suffix rather than skipping an oversized turn', () {
    final history = [
      message('user', 'tiny old question'),
      message('assistant', 'tiny old answer'),
      message('user', 'large middle question'),
      message('assistant', '文' * 1000),
      message('user', 'latest'),
    ];
    expect(
      ChatContext.select(
        history,
        systemPrompt: '',
        windowTokens: 800,
        outputTokens: 64,
      ),
      [history.last],
    );
  });

  test(
    'includes prompts, output reserve and message framing in the budget',
    () {
      final history = [message('user', '文' * 100)];
      expect(
        () => ChatContext.select(
          history,
          systemPrompt: '文' * 100,
          windowTokens: 700,
          outputTokens: 64,
        ),
        throwsA(isA<ChatContextException>()),
      );
      expect(
        ChatContext.select(
          history,
          systemPrompt: '',
          windowTokens: 700,
          outputTokens: 64,
        ),
        history,
      );
      expect(
        () => ChatContext.select(
          history,
          systemPrompt: '',
          windowTokens: 700,
          outputTokens: 300,
        ),
        throwsA(isA<ChatContextException>()),
      );
    },
  );

  test('latest message and appended evidence are never silently truncated', () {
    final current = message('user', 'question\nSources: ${'证据' * 5000}');
    expect(
      () => ChatContext.select([current], systemPrompt: '', windowTokens: 8192),
      throwsA(isA<ChatContextException>()),
    );
    expect(current['content'], endsWith('证据' * 5000));
  });

  test('non-ASCII and punctuation use a conservative estimate', () {
    expect(ChatContext.estimateTokens('abc'), 1);
    expect(ChatContext.estimateTokens('中文'), 4);
    expect(ChatContext.estimateTokens('😀'), 3);
    expect(ChatContext.estimateTokens('{}[]'), 4);
  });

  test('invalid saved budgets fall back to a safe default', () {
    for (final value in [null, '', 'broken', '-1', '900000', '0']) {
      expect(ChatContext.parseWindow(value), ChatContext.defaultWindowTokens);
    }
    expect(ChatContext.parseWindow('8192'), 8192);
  });

  test(
    'recognizes size errors without treating token quotas as context limits',
    () {
      for (final raw in [
        '{"error":{"code":"context_length_exceeded","message":"redacted"}}',
        '{"error":"context_length_exceeded"}',
        '{"error":{"type":"invalid_request_error","message":"prompt is too long: 100 > 80 tokens"}}',
        'maximum context length is 8192 tokens',
        'The input token count (9000) exceeds the maximum number of tokens allowed (8000).',
        'Input length must be less than 8192 tokens',
        '输入长度超过模型限制',
      ]) {
        expect(ChatContext.isServerLimit(raw), isTrue, reason: raw);
      }
      for (final raw in [
        '{"error":{"code":"rate_limit_exceeded","message":"tokens per minute exceeded"}}',
        'insufficient_quota',
        'invalid max_tokens value',
        'unknown model',
      ]) {
        expect(ChatContext.isServerLimit(raw), isFalse, reason: raw);
      }
    },
  );
}
