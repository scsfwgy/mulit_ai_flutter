import 'dart:async';

import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

enum AgentCapabilityResult { passed, inconclusive }

/// A harmless two-turn probe, with no chat, project, search or file access.
class AgentCapabilityCheck {
  AgentCapabilityCheck(this.client, this.model);
  final ModelApiClient client;
  final String model;
  void cancel() => client.cancel();

  Future<AgentCapabilityResult> run() async {
    try {
      return await _run().timeout(
        const Duration(seconds: 35),
        onTimeout: () {
          cancel();
          throw ApiException(
            T('i18n.agent_network_error'),
            kind: ApiErrorKind.network,
          );
        },
      );
    } finally {
      cancel();
    }
  }

  Future<AgentCapabilityResult> _run() async {
    const tools = <Map<String, dynamic>>[
      {
        'name': 'agent_probe',
        'description': 'Harmless compatibility check. Call with value ok.',
        'parameters': {
          'type': 'object',
          'properties': {
            'value': {
              'type': 'string',
              'enum': ['ok'],
            },
          },
          'required': ['value'],
          'additionalProperties': false,
        },
      },
    ];
    const prompt =
        'This is a tool compatibility check. First call agent_probe with value ok. After receiving its result, reply with OK using text only.';
    final messages = <Map<String, dynamic>>[
      {'role': 'user', 'content': 'Please run the compatibility check.'},
    ];
    final first = await client.toolTurn(
      model: model,
      systemPrompt: prompt,
      messages: messages,
      tools: tools,
      outputTokens: 512,
    );
    if (first.calls.length != 1) return AgentCapabilityResult.inconclusive;
    final call = first.calls.single;
    if (call.name != 'agent_probe' ||
        call.argumentError ||
        call.arguments.length != 1 ||
        call.arguments['value'] != 'ok') {
      return AgentCapabilityResult.inconclusive;
    }
    messages.add(first.message);
    appendModelToolResult(
      messages,
      client.provider.protocol,
      call,
      '{"value":"ok"}',
    );
    final second = await client.toolTurn(
      model: model,
      systemPrompt: prompt,
      messages: messages,
      tools: tools,
      outputTokens: 512,
      allowTools: false,
    );
    return second.calls.isEmpty && second.text.trim().isNotEmpty
        ? AgentCapabilityResult.passed
        : AgentCapabilityResult.inconclusive;
  }
}
