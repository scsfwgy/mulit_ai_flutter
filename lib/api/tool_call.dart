import 'dart:convert';

import 'package:mulit_ai_flutter/core/data.dart';

class ModelToolCall {
  const ModelToolCall(this.id, this.name, this.arguments);
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
  };

  factory ModelToolCall.fromJson(Map<String, dynamic> json) => ModelToolCall(
    json['id'] as String,
    json['name'] as String,
    Map<String, dynamic>.from(json['arguments'] as Map),
  );
}

class ModelToolTurn {
  const ModelToolTurn(
    this.message,
    this.text,
    this.calls,
    this.inputTokens,
    this.outputTokens,
  );
  final Map<String, dynamic> message;
  final String text;
  final List<ModelToolCall> calls;
  final int? inputTokens;
  final int? outputTokens;

  factory ModelToolTurn.parse(Map<String, dynamic> json, ApiProtocol protocol) {
    final calls = <ModelToolCall>[];
    final String text;
    final Map<String, dynamic> message;
    final Map usage;
    if (protocol == ApiProtocol.anthropic) {
      final reason = json['stop_reason'];
      if (reason != 'end_turn' && reason != 'tool_use') {
        throw const FormatException('Incomplete model turn');
      }
      final content = (json['content'] as List).cast<Map>();
      message = {'role': 'assistant', 'content': content};
      text = content
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join('\n');
      for (final block in content.where((b) => b['type'] == 'tool_use')) {
        calls.add(
          ModelToolCall(
            block['id'] as String,
            block['name'] as String,
            Map<String, dynamic>.from(block['input'] as Map),
          ),
        );
      }
      if ((reason == 'tool_use') != calls.isNotEmpty) {
        throw const FormatException('Invalid stop reason');
      }
      usage = json['usage'] as Map? ?? {};
    } else {
      final choice = (json['choices'] as List).first as Map;
      final reason = choice['finish_reason'];
      if (reason != 'stop' && reason != 'tool_calls') {
        throw const FormatException('Incomplete model turn');
      }
      final raw = choice['message'] as Map;
      text = raw['content'] as String? ?? '';
      final tools = raw['tool_calls'] as List? ?? [];
      message = {
        'role': 'assistant',
        'content': raw['content'],
        if (tools.isNotEmpty) 'tool_calls': tools,
        if (raw['reasoning_content'] is String)
          'reasoning_content': raw['reasoning_content'],
        if (raw['reasoning_details'] is List)
          'reasoning_details': raw['reasoning_details'],
      };
      for (final tool in tools.cast<Map>()) {
        final function = tool['function'] as Map;
        calls.add(
          ModelToolCall(
            tool['id'] as String,
            function['name'] as String,
            Map<String, dynamic>.from(
              jsonDecode(function['arguments'] as String) as Map,
            ),
          ),
        );
      }
      if ((reason == 'tool_calls') != calls.isNotEmpty) {
        throw const FormatException('Invalid finish reason');
      }
      usage = json['usage'] as Map? ?? {};
    }
    if (calls.length > 6 ||
        calls.map((c) => c.id).toSet().length != calls.length ||
        calls.any(
          (c) =>
              c.id.isEmpty ||
              c.id.length > 200 ||
              c.name.length > 100 ||
              jsonEncode(c.arguments).length > 60000,
        ) ||
        calls.isEmpty && text.trim().isEmpty) {
      throw const FormatException('Invalid tool calls');
    }
    final input =
        usage[protocol == ApiProtocol.anthropic
                ? 'input_tokens'
                : 'prompt_tokens']
            as int?;
    return ModelToolTurn(
      message,
      text,
      calls,
      input == null
          ? null
          : input +
                (protocol == ApiProtocol.anthropic
                    ? (usage['cache_creation_input_tokens'] as int? ?? 0) +
                          (usage['cache_read_input_tokens'] as int? ?? 0)
                    : 0),
      usage[protocol == ApiProtocol.anthropic
              ? 'output_tokens'
              : 'completion_tokens']
          as int?,
    );
  }
}

Map<String, dynamic> modelToolResult(
  ApiProtocol protocol,
  ModelToolCall call,
  String result,
) => protocol == ApiProtocol.anthropic
    ? {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': call.id, 'content': result},
        ],
      }
    : {'role': 'tool', 'tool_call_id': call.id, 'content': result};

void appendModelToolResult(
  List<Map<String, dynamic>> messages,
  ApiProtocol protocol,
  ModelToolCall call,
  String result,
) {
  final message = modelToolResult(protocol, call, result);
  if (protocol == ApiProtocol.anthropic &&
      messages.isNotEmpty &&
      messages.last['role'] == 'user' &&
      messages.last['content'] is List) {
    (messages.last['content'] as List).addAll(message['content'] as List);
  } else {
    messages.add(message);
  }
}
