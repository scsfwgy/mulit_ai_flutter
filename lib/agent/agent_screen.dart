import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/chat/assistant_markdown.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/settings/purchase_screen.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AgentSettingsScreen extends StatefulWidget {
  const AgentSettingsScreen({super.key});
  @override
  State<AgentSettingsScreen> createState() => _AgentSettingsScreenState();
}

class _AgentSettingsScreenState extends State<AgentSettingsScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _openHistory() async {
    final target = await Navigator.push<AgentChatRequest>(
      context,
      appPageRoute(builder: (_) => const AgentScreen()),
    );
    if (target != null && mounted) Navigator.pop(context, target);
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppPreferences.instance.setAgentEnabled(value);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (context, _) => Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: T('i18n.agent_title'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            IosSection(
              footer: T('i18n.agent_settings_detail'),
              children: [
                IosRow(
                  title: T('i18n.agent_enable'),
                  chevron: false,
                  trailing: CupertinoSwitch(
                    key: const Key('agent-enable'),
                    value: AppPreferences.instance.agentEnabled,
                    activeTrackColor: IosColors.blue,
                    onChanged: _saving ? null : _toggle,
                  ),
                ),
              ],
            ),
            IosSection(
              footer: T('i18n.agent_limits'),
              children: [
                IosRow(
                  key: const Key('agent-context-settings'),
                  title: T('i18n.agent_context'),
                  subtitle: ChatContext.windowLabel(
                    AppPreferences.instance.agentContextWindowTokens,
                  ),
                  onTap: () => Navigator.push<void>(
                    context,
                    appPageRoute(
                      builder: (_) => const ChatContextScreen(forAgent: true),
                    ),
                  ),
                ),
                IosRow(
                  title: T('i18n.agent_history'),
                  leading: Icon(
                    CupertinoIcons.check_mark_circled,
                    color: IosColors.blue,
                  ),
                  onTap: _openHistory,
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error!,
                  style: TextStyle(color: IosColors.destructive),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _repository = AgentStore();
  List<AgentTask>? _tasks;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final tasks = await _repository.tasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_failed'));
    }
  }

  Future<void> _delete(AgentTask task) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.agent_delete')),
        content: Text(T('i18n.agent_delete_detail')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(T('i18n.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(T('i18n.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || AgentRunner.isBusy) return;
    try {
      await _repository.delete(task);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_failed'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.agent_history'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: _tasks == null && _error == null
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              children: [
                IosSection(
                  footer: T('i18n.agent_chat_detail'),
                  children: [
                    if (_tasks?.isEmpty == true)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          T('i18n.agent_empty'),
                          style: TextStyle(color: IosColors.secondary),
                        ),
                      ),
                    for (final task in _tasks ?? <AgentTask>[])
                      IosRow(
                        title: task.goal,
                        subtitle: '${agentStatus(task)} · ${task.model}',
                        onTap: () async {
                          final target = await Navigator.push<AgentChatRequest>(
                            context,
                            appPageRoute(
                              builder: (_) => AgentTaskScreen(task: task),
                            ),
                          );
                          if (!context.mounted) return;
                          if (target != null) {
                            Navigator.pop(context, target);
                            return;
                          }
                          await _load();
                        },
                        trailing: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          minimumSize: Size.zero,
                          onPressed: () => _delete(task),
                          child: Icon(
                            CupertinoIcons.delete,
                            size: 18,
                            color: IosColors.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
                      style: TextStyle(color: IosColors.destructive),
                    ),
                  ),
              ],
            ),
    ),
  );
}

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

/// One recovery action at a time, shared by the chat card and task details.
class AgentTaskActions extends StatefulWidget {
  const AgentTaskActions({
    super.key,
    required this.task,
    this.onResume,
    this.onOpenChat,
    this.retryWithCurrentModel = false,
  });
  final AgentTask task;
  final VoidCallback? onResume;
  final ValueChanged<AgentChatRequest>? onOpenChat;
  final bool retryWithCurrentModel;

  @override
  State<AgentTaskActions> createState() => _AgentTaskActionsState();
}

class _AgentTaskActionsState extends State<AgentTaskActions> {
  AgentRecoveryAction? _nextAction;
  bool _opening = false;
  String? _error;

  Future<void> _open(AgentRecoveryAction action) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      switch (action) {
        case AgentRecoveryAction.resume:
          widget.onResume?.call();
        case AgentRecoveryAction.chat || AgentRecoveryAction.model:
          widget.onOpenChat?.call(
            AgentChatRequest(
              widget.task,
              changeModel: action == AgentRecoveryAction.model,
            ),
          );
        case AgentRecoveryAction.context:
          final previous = AppPreferences.instance.agentContextWindowTokens;
          await Navigator.push<void>(
            context,
            appPageRoute(
              builder: (_) => const ChatContextScreen(forAgent: true),
            ),
          );
          if (previous != AppPreferences.instance.agentContextWindowTokens) {
            _nextAction = AgentRecoveryAction.resume;
          }
        case AgentRecoveryAction.service:
          final provider = (await AgentStore().store.providers())
              .where((p) => p.id == widget.task.providerId)
              .firstOrNull;
          if (!mounted) return;
          final saved = await Navigator.push<bool>(
            context,
            appPageRoute(
              builder: (_) => provider == null
                  ? const ProviderScreen()
                  : ProviderEditor(config: provider),
            ),
          );
          if (saved == true && provider != null) {
            final updated = (await AgentStore().store.providers())
                .where((p) => p.id == provider.id)
                .firstOrNull;
            _nextAction =
                updated != null &&
                    updated.protocol == widget.task.protocol &&
                    (widget.task.endpoint.isEmpty ||
                        updated.baseUrl == widget.task.endpoint)
                ? AgentRecoveryAction.resume
                : AgentRecoveryAction.model;
          }
        case AgentRecoveryAction.settings:
          final target = await Navigator.push<AgentChatRequest>(
            context,
            appPageRoute(builder: (_) => const AgentSettingsScreen()),
          );
          if (!mounted) return;
          if (target != null) {
            widget.onOpenChat?.call(target);
            return;
          }
          if (AppPreferences.instance.agentEnabled) {
            _nextAction = widget.task.errorCode == 'i18n.agent_disabled'
                ? AgentRecoveryAction.resume
                : null;
          }
        case AgentRecoveryAction.purchase:
          await Navigator.push<void>(
            context,
            appPageRoute(builder: (_) => const PurchaseScreen()),
          );
          if (ApplePurchases.instance.canUse) {
            _nextAction = AgentRecoveryAction.resume;
          }
      }
    } catch (_) {
      if (mounted) _error = T('i18n.agent_save_failed');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.task.canResume) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: AppPreferences.instance,
      builder: (context, _) {
        var action = !AppPreferences.instance.agentEnabled
            ? AgentRecoveryAction.settings
            : widget.retryWithCurrentModel
            ? AgentRecoveryAction.resume
            : _nextAction ?? agentRecoveryAction(widget.task);
        if (action == AgentRecoveryAction.resume &&
            widget.onResume == null &&
            widget.onOpenChat != null) {
          action = AgentRecoveryAction.chat;
        }
        if (action == AgentRecoveryAction.model &&
            widget.task.topicId == null) {
          action = AgentRecoveryAction.service;
        }
        final enabled =
            !_opening &&
            !AgentRunner.isBusy &&
            (action != AgentRecoveryAction.resume || widget.onResume != null) &&
            (!{
                  AgentRecoveryAction.model,
                  AgentRecoveryAction.chat,
                }.contains(action) ||
                widget.onOpenChat != null);
        final label = switch (action) {
          AgentRecoveryAction.resume =>
            widget.retryWithCurrentModel
                ? 'i18n.retry_response'
                : 'i18n.agent_resume',
          AgentRecoveryAction.context => 'i18n.agent_adjust_context',
          AgentRecoveryAction.service => 'i18n.check_service_settings',
          AgentRecoveryAction.model => 'i18n.switch_model',
          AgentRecoveryAction.chat => 'i18n.agent_return_to_chat',
          AgentRecoveryAction.settings => 'i18n.agent_enable',
          AgentRecoveryAction.purchase => 'i18n.agent_check_access',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.retryWithCurrentModel ||
                action == AgentRecoveryAction.model)
              Text(
                T(
                  widget.retryWithCurrentModel
                      ? 'i18n.agent_model_changed_retry'
                      : 'i18n.agent_model_restart_detail',
                ),
                style: TextStyle(color: IosColors.secondary, fontSize: 13),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: IosColors.destructive, fontSize: 13),
              ),
            CupertinoButton(
              key: const Key('agent-recovery-action'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: Size.zero,
              onPressed: enabled ? () => _open(action) : null,
              child: Text(T(label)),
            ),
          ],
        );
      },
    );
  }
}

class AgentTaskScreen extends StatefulWidget {
  const AgentTaskScreen({
    super.key,
    required this.task,
    this.autoStart = false,
  });
  final AgentTask task;
  final bool autoStart;
  @override
  State<AgentTaskScreen> createState() => _AgentTaskScreenState();
}

class _AgentTaskScreenState extends State<AgentTaskScreen>
    with WidgetsBindingObserver {
  final _repository = AgentStore();
  late final AgentRunner _runner = AgentRunner(repository: _repository);
  bool _running = false;
  AgentRunner? _observed;
  AgentTask get _task => _observed?.currentTask ?? widget.task;
  bool get _busy =>
      _running ||
      (_observed != null &&
          AgentRunner.active == _observed &&
          _task.status == 'running');
  void _pause() {
    if (_observed != null && AgentRunner.active == _observed) {
      _observed!.pause();
    } else {
      _runner.pause();
    }
  }

  bool _showSteps = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runner.addListener(_changed);
    if (AgentRunner.active?.currentTask?.id == _task.id) {
      _observed = AgentRunner.active;
      _observed!.addListener(_changed);
    }
    if (widget.autoStart) unawaited(_run());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _pause();
    }
  }

  Future<void> _run() async {
    if (_busy || AgentRunner.isBusy) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await _runner.run(_task);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_save_failed'));
    } finally {
      if (mounted) {
        setState(() => _running = false);
      } else {
        _runner.dispose();
      }
    }
  }

  Future<void> _artifact(
    Map<String, dynamic> artifact, {
    bool share = false,
  }) async {
    try {
      await openAgentArtifact(context, _task, artifact, share: share);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.attachment_unavailable'));
    }
  }

  void _link(String? value) {
    if (value == null) return;
    final uri = safeSearchUrl(value);
    if (uri != null) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _observed?.removeListener(_changed);
    _runner.removeListener(_changed);
    // An in-flight run owns its cleanup until it finishes, even after navigation.
    if (!_running) _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return AnimatedBuilder(
      animation: AppPreferences.instance,
      builder: (context, _) => Scaffold(
        backgroundColor: IosColors.background,
        appBar: iosAppBar(
          title: T('i18n.agent_title'),
          leading: IosNavButton(
            icon: CupertinoIcons.back,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: ListView(
            children: [
              IosSection(
                footer: T('i18n.agent_limits'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      task.goal,
                      style: TextStyle(color: IosColors.label, fontSize: 17),
                    ),
                  ),
                  IosRow(
                    title: T('i18n.agent_model'),
                    subtitle: task.model,
                    chevron: false,
                  ),
                  IosRow(
                    title: _busy ? agentActivity(task) : agentStatus(task),
                    subtitle: F('i18n.agent_progress', [
                      task.rounds,
                      task.calls,
                    ]),
                    chevron: false,
                    trailing: _busy ? const CupertinoActivityIndicator() : null,
                  ),
                  if (task.error != null || _error != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _error ?? task.error!,
                        style: TextStyle(color: IosColors.destructive),
                      ),
                    ),
                  if (_busy || task.canResume)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: _busy
                          ? IosPrimaryButton(
                              label: 'i18n.agent_pause',
                              onPressed: _pause,
                            )
                          : AgentTaskActions(
                              key: ValueKey(task.id),
                              task: task,
                              onResume: _run,
                              onOpenChat: (target) =>
                                  Navigator.pop(context, target),
                            ),
                    ),
                ],
              ),
              if (task.contextTokens > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(
                    F('i18n.agent_context_usage', [
                      task.contextTokens,
                      task.contextWindowTokens,
                    ]),
                    style: TextStyle(color: IosColors.secondary),
                  ),
                ),
              if (task.contextCompacted)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    T('i18n.agent_context_compacted'),
                    style: TextStyle(color: IosColors.secondary),
                  ),
                ),
              if (task.answer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: AssistantMarkdown(data: task.answer, onTapLink: _link),
                ),
              if (task.artifacts.isNotEmpty)
                IosSection(
                  title: T('i18n.agent_artifacts'),
                  children: [
                    for (final artifact in task.artifacts)
                      IosRow(
                        title: artifact['name'] as String,
                        onTap: () => _artifact(artifact),
                        trailing: CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          minimumSize: Size.zero,
                          onPressed: () => _artifact(artifact, share: true),
                          child: Icon(
                            CupertinoIcons.share,
                            color: IosColors.blue,
                          ),
                        ),
                      ),
                  ],
                ),
              IosSection(
                children: [
                  IosRow(
                    title: T('i18n.agent_steps'),
                    subtitle: _busy ? agentActivity(task) : null,
                    onTap: () => setState(() => _showSteps = !_showSteps),
                  ),
                  if (_showSteps && task.requests.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            T('i18n.agent_requests'),
                            style: TextStyle(color: IosColors.label),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            const JsonEncoder.withIndent('  ')
                                .convert(task.requests),
                            style: TextStyle(
                              color: IosColors.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_showSteps)
                    for (final step in task.steps)
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${agentToolLabel(step['name'] as String)} · ${T(switch (step['status']) {
                                'completed' => 'i18n.agent_completed',
                                'failed' => 'i18n.agent_failed_status',
                                'skipped' => 'i18n.agent_skipped',
                                'running' => _busy ? 'i18n.agent_running' : 'i18n.agent_interrupted',
                                _ => 'i18n.agent_pending',
                              })}',
                              style: TextStyle(color: IosColors.label),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              const JsonEncoder.withIndent('  ').convert({
                                'arguments': step['arguments'],
                                if (step['result'] != null)
                                  'result': step['result'],
                              }),
                              style: TextStyle(
                                color: IosColors.secondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
              if (task.sources.isNotEmpty)
                IosSection(
                  title: T('i18n.agent_evidence'),
                  children: [
                    for (final source in task.sources)
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: source['url'] == null
                                  ? null
                                  : () => _link(source['url'] as String),
                              child: Text(
                                '[${source['label']}] ${source['title']}',
                                style: TextStyle(color: IosColors.blue),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              source['excerpt'] as String? ?? '',
                              style: TextStyle(
                                color: IosColors.secondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  F('i18n.agent_usage', [
                    task.inputTokens,
                    task.outputTokens,
                    task.usageComplete
                        ? T('i18n.agent_reported_usage')
                        : T('i18n.agent_partial_usage'),
                  ]),
                  style: TextStyle(color: IosColors.secondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String agentToolLabel(String name) => T(switch (name) {
  'search_web' => 'i18n.agent_tool_search',
  'read_webpage' => 'i18n.agent_tool_read',
  'search_project' => 'i18n.agent_tool_project',
  'read_project_document' => 'i18n.agent_tool_document',
  'save_artifact' => 'i18n.agent_tool_save',
  _ => 'i18n.agent_tool_unknown',
});

Future<void> openAgentArtifact(
  BuildContext context,
  AgentTask task,
  Map<String, dynamic> artifact, {
  bool share = false,
}) async {
  final file = await AgentStore().artifactFile(task, artifact);
  if (share) {
    if (isDesktopApp) {
      final location = await files.getSaveLocation(
        suggestedName: artifact['name'] as String,
      );
      if (location != null && location.path != file.path) {
        await file.copy(location.path);
      }
    } else {
      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: artifact['name'] as String,
              mimeType: 'text/plain',
            ),
          ],
          fileNameOverrides: [artifact['name'] as String],
          sharePositionOrigin: origin,
        ),
      );
    }
    return;
  }
  final content = await file.readAsString();
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    appPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: IosColors.background,
        appBar: iosAppBar(
          title: artifact['name'] as String,
          leading: IosNavButton(
            icon: CupertinoIcons.back,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: (artifact['name'] as String).endsWith('.md')
                ? AssistantMarkdown(
                    data: content,
                    onTapLink: (url) {
                      final uri = url == null ? null : safeSearchUrl(url);
                      if (uri != null) {
                        unawaited(
                          launchUrl(uri, mode: LaunchMode.externalApplication),
                        );
                      }
                    },
                  )
                : SelectableText(
                    content,
                    style: TextStyle(color: IosColors.label),
                  ),
          ),
        ),
      ),
    ),
  );
}
