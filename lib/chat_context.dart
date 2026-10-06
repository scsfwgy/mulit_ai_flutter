import 'dart:convert';

/// A local estimate, not a tokenizer or a claim about a model's actual limit.
abstract final class ChatContext {
  static const settingKey = 'chat_context_window_tokens';
  static const defaultWindowTokens = 32768;
  static const replyReserveTokens = 4096;
  static const windowOptions = [8192, 16384, 32768, 65536, 131072, 262144];
  static const limitMessage = '当前消息、提示词或搜索内容超过上下文预算。请缩短内容，或在上下文设置中调整预算。';
  static const serverLimitMessage =
      '模型上下文已超出限制。请在上下文设置中降低预算后重试，或新建对话；单条消息过长时请缩短内容。';

  static int parseWindow(String? value) {
    final parsed = int.tryParse(value ?? '');
    return windowOptions.contains(parsed) ? parsed! : defaultWindowTokens;
  }

  // ASCII prose averages several characters per token; non-ASCII, code and
  // punctuation get a conservative estimate. Include message framing separately.
  static int estimateTokens(String text) {
    var asciiLetters = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (rune <= 0x7f &&
          ((rune >= 65 && rune <= 90) ||
              (rune >= 97 && rune <= 122) ||
              (rune >= 48 && rune <= 57) ||
              rune == 32)) {
        asciiLetters++;
      } else {
        other += rune > 0xffff
            ? 3
            : rune > 0x7f
            ? 2
            : 1;
      }
    }
    return (asciiLetters + 2) ~/ 3 + other;
  }

  /// Keeps the latest user turn and a contiguous suffix of complete older turns.
  /// Wire content must already include search evidence and historical sources.
  static List<Map<String, String>> select(
    List<Map<String, String>> messages, {
    required String systemPrompt,
    required int windowTokens,
    int outputTokens = replyReserveTokens,
  }) {
    if (messages.isEmpty) return messages;
    final budget = windowTokens - outputTokens - 256;
    var used = estimateTokens(systemPrompt) + 8;
    int cost(Map<String, String> message) =>
        estimateTokens(message['content'] ?? '') + 8;
    final starts = <int>[
      for (var i = 0; i < messages.length; i++)
        if (messages[i]['role'] == 'user') i,
    ];
    // Legacy or externally supplied histories may contain only assistant text.
    if (starts.isEmpty) starts.add(0);
    var start = starts.last;
    for (var i = start; i < messages.length; i++) {
      used += cost(messages[i]);
    }
    if (used > budget) throw const ChatContextException(limitMessage);
    for (var turn = starts.length - 2; turn >= 0; turn--) {
      final candidate = starts[turn];
      var turnCost = 0;
      for (var i = candidate; i < start; i++) {
        turnCost += cost(messages[i]);
      }
      if (used + turnCost > budget) break;
      used += turnCost;
      start = candidate;
    }
    return messages.sublist(start);
  }

  /// Recognize provider error codes and explicit size errors, not quota/token
  /// rate errors. Never include the response body in the resulting UI message.
  static bool isServerLimit(String raw) {
    String detail = '';
    try {
      final json = jsonDecode(raw);
      if (json is Map) {
        final error = json['error'];
        if (error is String) {
          detail = error;
        } else {
          final fields = error is Map ? error : json;
          detail = [
            'code',
            'type',
            'message',
          ].map((key) => fields[key]).whereType<String>().join(' ');
        }
      }
    } catch (_) {
      detail = raw;
    }
    final lower = detail.toLowerCase();
    return lower.contains('context_length_exceeded') ||
        lower.contains('max_context_length') ||
        lower.contains('context_window_exceeded') ||
        lower.contains('prompt_too_long') ||
        lower.contains('input_too_long') ||
        RegExp(r'(maximum|max) context (length|window)').hasMatch(lower) ||
        RegExp(r'(prompt|input|context|messages?) (is |are )?too long')
            .hasMatch(lower) ||
        RegExp(r'(context length|context window).{0,80}(exceed|limit)')
            .hasMatch(lower) ||
        RegExp(r'input token count.{0,80}(exceed|maximum)').hasMatch(lower) ||
        RegExp(r'input length.{0,80}(less than|smaller than|exceed|maximum)')
            .hasMatch(lower) ||
        RegExp(r'(上下文|输入|提示词).{0,30}(超出|超过|过长)').hasMatch(detail);
  }
}

class ChatContextException implements Exception {
  const ChatContextException(this.message);
  final String message;
}
