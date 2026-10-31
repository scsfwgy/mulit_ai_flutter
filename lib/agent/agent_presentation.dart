import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/agent_tools.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

String agentStatus(AgentTask task) => T(switch (task.status) {
  'completed' =>
    task.finishNotice == null
        ? 'i18n.agent_completed'
        : 'i18n.agent_partial_status',
  'failed' => 'i18n.agent_failed_status',
  'running' =>
    AgentRunner.active?.currentTask?.id == task.id
        ? 'i18n.agent_running'
        : 'i18n.agent_interrupted',
  _ => 'i18n.agent_paused',
});

String agentActivity(AgentTask task) {
  if (task.finalReady) return T('i18n.agent_saving_result');
  if (task.pending.firstOrNull case final pending?) {
    final index = pending['step'];
    if (index is int &&
        index >= 0 &&
        index < task.steps.length &&
        task.steps[index]['status'] == 'running') {
      return agentToolLabel(pending['name'] as String);
    }
    return T('i18n.agent_preparing');
  }
  if (task.requests.lastOrNull?['status'] == 'retrying') {
    return T('i18n.agent_retry_wait');
  }
  return T(
    task.requests.lastOrNull?['status'] == 'running'
        ? task.requests.last['tools_enabled'] == false
              ? 'i18n.agent_organizing_answer'
              : 'i18n.agent_waiting_model'
        : 'i18n.agent_preparing',
  );
}

String agentStepStatus(Map<String, dynamic> step, {required bool running}) =>
    T(switch (step['status']) {
      'completed' => 'i18n.agent_completed',
      'failed' => 'i18n.agent_failed_status',
      'skipped' =>
        step['result'] is Map && step['result']['code'] == 'task_updated'
            ? 'i18n.agent_step_updated'
            : 'i18n.agent_skipped',
      'running' => running ? 'i18n.agent_running' : 'i18n.agent_interrupted',
      _ => 'i18n.agent_pending',
    });

String? agentStepDetail(Map<String, dynamic> step) {
  final args = step['arguments'] is Map ? step['arguments'] as Map : const {};
  final result = step['result'] is Map ? step['result'] as Map : const {};
  final subject = switch (step['name']) {
    'search_web' || 'search_project' => args['query'],
    'read_webpage' =>
      args['url'] is String ? Uri.tryParse(args['url'] as String)?.host : null,
    'read_project_document' => result['name'],
    'save_artifact' => args['name'],
    _ => null,
  };
  final lines = <String>[];
  if (subject is String && subject.trim().isNotEmpty) {
    final text = subject.replaceAll(RegExp(r'\s+'), ' ').trim();
    lines.add(
      text.runes.length > 140
          ? '${String.fromCharCodes(text.runes.take(140))}…'
          : text,
    );
  }
  if (step['status'] == 'completed') {
    if (result['sources'] is List) {
      lines.add(
        F('i18n.agent_found_sources', [(result['sources'] as List).length]),
      );
    } else if (result['text'] is String) {
      lines.add(
        F('i18n.agent_extracted_chars', [
          (result['text'] as String).runes.length,
        ]),
      );
    }
  }
  return lines.isEmpty ? null : lines.join(' · ');
}

class AgentChatRequest {
  const AgentChatRequest(this.task, {this.changeModel = false});
  final AgentTask task;
  final bool changeModel;
}

enum AgentRecoveryAction {
  resume,
  context,
  service,
  model,
  chat,
  settings,
  purchase,
}

AgentRecoveryAction agentRecoveryAction(AgentTask task) {
  if (task.contextBlocked) return AgentRecoveryAction.context;
  final request = task.requests.lastOrNull;
  final code = task.errorCode ?? (task.error == null ? null : request?['code']);
  if (code == 'other' && request?['http_status'] is int) {
    final status = request!['http_status'] as int;
    if (status == 429 || status >= 500) return AgentRecoveryAction.resume;
  }
  return switch (code) {
    'context' => AgentRecoveryAction.context,
    'auth' ||
    'other' ||
    'invalid_response' ||
    'unknown' ||
    'i18n.this_service_has_no_api' => AgentRecoveryAction.service,
    'model' ||
    'tools_disabled' ||
    'i18n.agent_provider_changed' => AgentRecoveryAction.model,
    'i18n.agent_chat_changed' => AgentRecoveryAction.chat,
    'i18n.agent_disabled' => AgentRecoveryAction.settings,
    'i18n.agent_access' => AgentRecoveryAction.purchase,
    _ => AgentRecoveryAction.resume,
  };
}
