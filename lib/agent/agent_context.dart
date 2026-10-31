import 'dart:convert';

import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/data.dart';

class AgentContextException implements Exception {
  const AgentContextException(this.requiredTokens, this.windowTokens);
  final int requiredTokens;
  final int windowTokens;
}

/// Only the request copy is shortened; durable tool results remain unchanged.
abstract final class AgentContext {
  static const settingKey = 'agent_context_window_tokens';

  static ({List<Map<String, dynamic>> messages, int tokens, bool compacted})
  prepare({
    required ApiProtocol protocol,
    required String model,
    required String prompt,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    required int windowTokens,
    int outputTokens = 4096,
    bool allowTools = true,
    int? preserveFrom,
  }) {
    Object? copy(Object? v) => v is Map
        ? v.map<String, dynamic>(
            (k, value) => MapEntry(k as String, copy(value)),
          )
        : v is List
        ? v.map(copy).toList()
        : v;
    final wire = messages
        .map((m) => Map<String, dynamic>.from(copy(m) as Map))
        .toList();
    int estimate() => estimateToolTokens(
      modelToolBody(
        protocol,
        model,
        prompt,
        wire,
        tools,
        outputTokens: outputTokens,
        allowTools: allowTools,
      ),
    );
    var tokens = estimate();
    var compacted = false;
    final results = <Map<String, dynamic>>[];
    for (final message in wire) {
      if (message['role'] == 'tool') results.add(message);
      if (message['role'] == 'user' && message['content'] is List) {
        results.addAll(
          (message['content'] as List).whereType<Map<String, dynamic>>().where(
            (b) => b['type'] == 'tool_result',
          ),
        );
      }
    }
    // Keep call IDs, arguments and provider signatures intact, even when excerpts shrink.
    for (final limit in [2000, 1000, 500, 200, 0]) {
      if (tokens <= windowTokens) break;
      for (final result in results.take(
        (results.length - 1).clamp(0, results.length),
      )) {
        if (result['content'] is String) {
          result['content'] = _excerpt(result['content'] as String, limit);
        }
      }
      tokens = estimate();
      compacted = true;
    }
    for (final limit in [2000, 1000, 500, 200]) {
      if (tokens <= windowTokens || results.isEmpty) break;
      final result = results.last;
      if (result['content'] is String) {
        result['content'] = _excerpt(result['content'] as String, limit);
      }
      tokens = estimate();
      compacted = true;
    }
    bool human(Map<String, dynamic> m) =>
        m['role'] == 'user' &&
        (m['content'] is! List ||
            !(m['content'] as List).any(
              (p) => p is Map && p['type'] == 'tool_result',
            ));
    // Added instructions belong to the same task: keep its original goal and tools.
    var protected = preserveFrom ?? wire.lastIndexWhere(human);
    while (tokens > windowTokens) {
      final next = wire.indexWhere(human, 1);
      if (next < 0 || next > protected) break;
      wire.removeRange(0, next);
      protected -= next;
      tokens = estimate();
      compacted = true;
    }
    if (tokens > windowTokens) {
      throw AgentContextException(tokens, windowTokens);
    }
    return (messages: wire, tokens: tokens, compacted: compacted);
  }

  static String _excerpt(String encoded, int limit) {
    try {
      var changed = false;
      Object? trim(Object? value, [String? key]) {
        if (value is String &&
            ['text', 'excerpt'].contains(key) &&
            value.runes.length > limit) {
          changed = true;
          final runes = value.runes.toList();
          final tail = limit ~/ 4;
          return '${String.fromCharCodes(runes.take(limit - tail))}…${String.fromCharCodes(runes.skip(runes.length - tail))}';
        }
        if (value is Map) {
          return value.map((k, v) => MapEntry(k, trim(v, '$k')));
        }
        if (value is List) return value.map((v) => trim(v)).toList();
        return value;
      }

      final value = trim(jsonDecode(encoded));
      if (changed && value is Map) value['context_note'] = 'Excerpts shortened for context; full output is retained in the execution log. Read specific sources again if needed.';
      return changed ? jsonEncode(value) : encoded;
    } on FormatException {
      return encoded;
    }
  }
}
