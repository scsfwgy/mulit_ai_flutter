import 'dart:convert';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';

Map<String, dynamic> modelToolBody(
  ApiProtocol protocol,
  String model,
  String prompt,
  List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>> tools, {
  int outputTokens = 4096,
  bool allowTools = true,
}) {
  final anthropic = protocol == ApiProtocol.anthropic;
  return {
    'model': model,
    'stream': false,
    'max_tokens': outputTokens,
    'messages': [
      if (!anthropic) {'role': 'system', 'content': prompt},
      ...messages,
    ],
    if (anthropic) 'system': prompt,
    if (!allowTools) 'tool_choice': anthropic ? {'type': 'none'} : 'none',
    'tools': tools
        .map(
          (tool) => anthropic
              ? {
                  'name': tool['name'],
                  'description': tool['description'],
                  'input_schema': tool['parameters'],
                }
              : {'type': 'function', 'function': tool},
        )
        .toList(),
  };
}

/// Binary payload size is not its model token cost; use the attachment estimates.
int estimateToolTokens(Map<String, dynamic> body) {
  var attachments = 0;
  Object? withoutBinary(Object? value) {
    if (value is Map) {
      if (['image', 'image_url', 'document', 'file'].contains(value['type'])) {
        attachments += value['type'] == 'image' || value['type'] == 'image_url'
            ? 2048
            : 4096;
        return {'type': value['type']};
      }
      return value.map((k, v) => MapEntry(k, withoutBinary(v)));
    }
    if (value is List) return value.map(withoutBinary).toList();
    return value;
  }

  final text = jsonEncode(withoutBinary(body));
  return ChatContext.estimateTokens(text) +
      attachments +
      (body['max_tokens'] as int? ??
          body['max_completion_tokens'] as int? ??
          4096);
}

class ModelTurnException extends FormatException {
  const ModelTurnException(
    this.code, {
    this.finishReason,
    this.inputTokens,
    this.outputTokens,
  }) : super(code);
  final String code;
  final String? finishReason;
  final int? inputTokens;
  final int? outputTokens;
}

class ModelToolCall {
  const ModelToolCall(
    this.id,
    this.name,
    this.arguments, {
    this.argumentError = false,
  });
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final bool argumentError;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    if (argumentError) 'argumentError': true,
  };

  factory ModelToolCall.fromJson(Map<String, dynamic> json) => ModelToolCall(
    json['id'] as String,
    json['name'] as String,
    Map<String, dynamic>.from(json['arguments'] as Map),
    argumentError: json['argumentError'] as bool? ?? false,
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
    final anthropic = protocol == ApiProtocol.anthropic;
    final usage = json['usage'] is Map ? json['usage'] as Map : const {};
    int? count(String key) => usage[key] is int && (usage[key] as int) >= 0
        ? usage[key] as int
        : null;
    final input = count(anthropic ? 'input_tokens' : 'prompt_tokens');
    final inputTokens = input == null
        ? null
        : input +
              (anthropic
                  ? (count('cache_creation_input_tokens') ?? 0) +
                        (count('cache_read_input_tokens') ?? 0)
                  : 0);
    final outputTokens = count(
      anthropic ? 'output_tokens' : 'completion_tokens',
    );
    String? reason;
    Never reject(String code) => throw ModelTurnException(
      code,
      finishReason: reason,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
    try {
      final choice = anthropic
          ? json
          : (json['choices'] as List).firstOrNull as Map?;
      if (choice == null) reject('invalid_response');
      reason = choice[anthropic ? 'stop_reason' : 'finish_reason'] as String?;
      if (reason != null && !RegExp(r'^[a-z_]{1,64}$').hasMatch(reason)) {
        reason = 'unknown';
      }
      if ([
        'length',
        'max_tokens',
        'model_context_window_exceeded',
      ].contains(reason)) {
        reject('output_limit');
      }
      if (['insufficient_system_resource', 'aborted'].contains(reason)) {
        reject('provider_interrupted');
      }
      if (['content_filter', 'refusal'].contains(reason)) reject('refused');
      if (!(anthropic
              ? ['end_turn', 'stop_sequence', 'tool_use']
              : ['stop', 'tool_calls'])
          .contains(reason)) {
        reject('invalid_response');
      }
      final raw = anthropic ? json : choice['message'] as Map;
      final calls = <ModelToolCall>[];
      final Map<String, dynamic> message;
      final String text;
      void addCall(
        Object? id,
        Object? name,
        Object? arguments, {
        bool invalid = false,
      }) {
        if (id is! String ||
            id.isEmpty ||
            id.length > 200 ||
            name is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(name)) {
          reject('invalid_response');
        }
        calls.add(
          ModelToolCall(
            id,
            name,
            arguments is Map ? Map<String, dynamic>.from(arguments) : {},
            argumentError: invalid || arguments is! Map,
          ),
        );
      }

      if (anthropic) {
        final content = (raw['content'] as List).cast<Map>();
        message = {'role': 'assistant', 'content': content};
        text = content
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'] as String)
            .join('\n');
        for (final block in content.where((b) => b['type'] == 'tool_use')) {
          addCall(block['id'], block['name'], block['input']);
        }
      } else {
        final content = raw['content'];
        text = content is List
            ? content
                  .whereType<Map>()
                  .where((p) => p['type'] == 'text')
                  .map((p) => p['text'] as String)
                  .join('\n')
            : content as String? ?? '';
        final tools = raw['tool_calls'] as List? ?? [];
        message = {
          'role': 'assistant',
          'content': content,
          if (tools.isNotEmpty) 'tool_calls': tools,
          if (raw['reasoning_content'] is String)
            'reasoning_content': raw['reasoning_content'],
          if (raw['reasoning_details'] is List)
            'reasoning_details': raw['reasoning_details'],
        };
        for (final tool in tools.cast<Map>()) {
          final function = tool['function'] as Map;
          Object? arguments;
          try {
            arguments = jsonDecode(function['arguments'] as String);
          } on FormatException {
            /* Return a paired tool error so the model can correct its arguments. */
          }
          addCall(tool['id'], function['name'], arguments);
        }
      }
      if (calls.length > 64 ||
          calls.map((c) => c.id).toSet().length != calls.length) {
        reject('invalid_response');
      }
      if (calls.isEmpty && reason == (anthropic ? 'tool_use' : 'tool_calls')) {
        reject('invalid_response');
      }
      if (calls.isEmpty && text.trim().isEmpty) reject('empty_response');
      return ModelToolTurn(message, text, calls, inputTokens, outputTokens);
    } on ModelTurnException {
      rethrow;
    } on FormatException {
      reject('invalid_response');
    } on TypeError {
      reject('invalid_response');
    } on RangeError {
      reject('invalid_response');
    }
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
