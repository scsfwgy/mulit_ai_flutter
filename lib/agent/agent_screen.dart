import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/chat/assistant_markdown.dart';
import 'package:mulit_ai_flutter/chat/chat_model_selector.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class AgentSettingsScreen extends StatefulWidget {
  const AgentSettingsScreen({super.key});
  @override
  State<AgentSettingsScreen> createState() => _AgentSettingsScreenState();
}

class _AgentSettingsScreenState extends State<AgentSettingsScreen> {
  bool _saving = false;
  String? _error;

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
                  title: T('i18n.agent_tasks'),
                  leading: Icon(
                    CupertinoIcons.check_mark_circled,
                    color: IosColors.blue,
                  ),
                  onTap: () => Navigator.push<void>(
                    context,
                    appPageRoute(builder: (_) => const AgentScreen()),
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
    ),
  );
}

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key, this.providerId, this.model, this.projectId});
  final int? providerId;
  final String? model;
  final int? projectId;
  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final _goal = TextEditingController();
  final _repository = AgentStore();
  List<AgentTask> _tasks = [];
  List<ProviderConfig> _providers = [];
  List<ChatProject> _projects = [];
  int? _providerId;
  int? _projectId;
  String? _model;
  String? _error;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _providerId = widget.providerId;
    _model = widget.model;
    _projectId = widget.projectId;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final tasks = await _repository.tasks();
      await StorefrontPolicy.instance.refresh();
      final providers = (await ChatStore.instance.providers())
          .where(
            (p) => !StorefrontPolicy.instance.blocks(
              p.baseUrl,
              presetId: p.presetId,
              model: p.model,
            ),
          )
          .toList();
      final projects = await ChatStore.instance.projects();
      final selected =
          providers.where((p) => p.id == _providerId).firstOrNull ??
          providers.firstOrNull;
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _providers = providers;
        _projects = projects;
        if (_projectId != null && !projects.any((p) => p.id == _projectId)) {
          _projectId = null;
        }
        if (selected?.id != _providerId) _model = selected?.model;
        _providerId = selected?.id;
        _model ??= selected?.model;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = T('i18n.agent_failed');
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseModel() async {
    if (_providers.isEmpty) return;
    final selection = await Navigator.push<ChatModelSelection>(
      context,
      appPageRoute(
        builder: (_) => ChatModelSelector(
          providers: _providers,
          topics: const [],
          providerId: _providerId,
          model: _model,
          loadCachedModels: ChatStore.instance.cachedModels,
          loadModels: (p) async {
            final client = ModelApiClient(
              p,
              await ChatStore.instance.apiKey(p.id) ?? '',
            );
            try {
              return await client.fetchModels();
            } finally {
              client.cancel();
            }
          },
        ),
      ),
    );
    if (selection != null && mounted) {
      setState(() {
        _providerId = selection.providerId;
        _model = selection.model;
      });
    }
  }

  Future<void> _chooseProject() async {
    final choice = await showAppModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(T('i18n.project_space')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, -1),
            child: Text(T('i18n.agent_no_project')),
          ),
          for (final project in _projects)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, project.id),
              child: Text(project.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (choice != null && mounted) {
      setState(() => _projectId = choice == -1 ? null : choice);
    }
  }

  Future<void> _open(AgentTask task, {bool start = false}) async {
    await Navigator.push<void>(
      context,
      appPageRoute(
        builder: (_) => AgentTaskScreen(task: task, autoStart: start),
      ),
    );
    await _load();
  }

  Future<void> _start() async {
    if (_starting ||
        !AppPreferences.instance.agentEnabled ||
        AgentRunner.isBusy ||
        _goal.text.trim().isEmpty) {
      return;
    }
    final provider = _providers.where((p) => p.id == _providerId).firstOrNull;
    if (provider == null || _model == null) return;
    final model = _model!;
    final projectId = _projectId;
    final goal = _goal.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final prompt = await ChatStore.instance.chatSystemPrompt(
        provider.id,
        model,
        projectId: projectId,
      );
      if (!mounted || !AppPreferences.instance.agentEnabled) return;
      final task = AgentTask(
        providerId: provider.id,
        model: model,
        protocol: provider.protocol,
        endpoint: provider.baseUrl,
        projectId: projectId,
        goal: goal,
        systemPrompt: prompt,
      );
      await _repository.save(task);
      if (!mounted) return;
      _goal.clear();
      if (mounted) await _open(task, start: true);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_failed'));
    } finally {
      if (mounted) setState(() => _starting = false);
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
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (context, _) => Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: T('i18n.agent_tasks'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                children: [
                  IosSection(
                    footer: T('i18n.agent_task_detail'),
                    children: [
                      IosRow(
                        title: T('i18n.agent_model'),
                        subtitle:
                            '${_providers.where((p) => p.id == _providerId).firstOrNull?.name ?? T('i18n.agent_no_model')} · ${_model ?? ''}',
                        onTap: _starting ? null : _chooseModel,
                      ),
                      IosRow(
                        title: T('i18n.project_space'),
                        subtitle:
                            _projects
                                .where((p) => p.id == _projectId)
                                .firstOrNull
                                ?.name ??
                            T('i18n.agent_no_project'),
                        onTap: _starting ? null : _chooseProject,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: CupertinoTextField(
                          key: const Key('agent-goal'),
                          controller: _goal,
                          readOnly: _starting,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 4000,
                          placeholder: T('i18n.agent_goal_hint'),
                          style: TextStyle(color: IosColors.label),
                          decoration: BoxDecoration(
                            color: IosColors.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: ValueListenableBuilder(
                          valueListenable: _goal,
                          builder: (context, _, _) => IosPrimaryButton(
                            label: 'i18n.agent_start',
                            icon: CupertinoIcons.play_fill,
                            onPressed:
                                !AppPreferences.instance.agentEnabled ||
                                    _starting ||
                                    _providerId == null ||
                                    _goal.text.trim().isEmpty
                                ? null
                                : _start,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!AppPreferences.instance.agentEnabled)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Text(
                        T('i18n.agent_disabled'),
                        style: TextStyle(color: IosColors.secondary),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _error!,
                        style: TextStyle(color: IosColors.destructive),
                      ),
                    ),
                  IosSection(
                    title: T('i18n.agent_history'),
                    children: [
                      if (_tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            T('i18n.agent_empty'),
                            style: TextStyle(color: IosColors.secondary),
                          ),
                        ),
                      for (final task in _tasks)
                        IosRow(
                          title: task.goal,
                          subtitle: '${agentStatus(task)} · ${task.model}',
                          onTap: () => _open(task),
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
                  const SizedBox(height: 24),
                ],
              ),
      ),
    ),
  );
}

String agentStatus(AgentTask task) => T(switch (task.status) {
  'completed' => 'i18n.agent_completed',
  'failed' => 'i18n.agent_failed_status',
  'running' =>
    AgentRunner.isBusy ? 'i18n.agent_running' : 'i18n.agent_interrupted',
  _ => 'i18n.agent_paused',
});

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
  bool _showSteps = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runner.addListener(_changed);
    if (widget.autoStart) unawaited(_run());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // shortcut: Pause in background until native scheduling is device-validated.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _runner.pause();
    }
  }

  Future<void> _run() async {
    if (_running || AgentRunner.isBusy) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await _runner.run(widget.task);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_save_failed'));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _artifact(
    Map<String, dynamic> artifact, {
    bool share = false,
  }) async {
    try {
      final file = await _repository.artifactFile(widget.task, artifact);
      if (share) {
        if (isDesktopApp) {
          final location = await files.getSaveLocation(
            suggestedName: artifact['name'] as String,
          );
          if (location != null && location.path != file.path) {
            await file.copy(location.path);
          }
        } else {
          if (!mounted) return;
          final box = context.findRenderObject() as RenderBox?;
          final origin = box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size;
          await SharePlus.instance.share(
            ShareParams(
              fileNameOverrides: [artifact['name'] as String],
              files: [
                XFile(
                  file.path,
                  name: artifact['name'] as String,
                  mimeType: 'text/plain',
                ),
              ],
              sharePositionOrigin: origin,
            ),
          );
        }
      } else {
        final content = await file.readAsString();
        if (mounted) {
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
                        ? AssistantMarkdown(data: content, onTapLink: _link)
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
      }
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
    _runner.removeListener(_changed);
    _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
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
                    title: agentStatus(task),
                    subtitle: F('i18n.agent_progress', [
                      task.rounds,
                      task.calls,
                    ]),
                    chevron: false,
                    trailing: _running
                        ? const CupertinoActivityIndicator()
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: IosPrimaryButton(
                      label: _running
                          ? 'i18n.agent_pause'
                          : 'i18n.agent_resume',
                      onPressed: _running
                          ? _runner.pause
                          : !AppPreferences.instance.agentEnabled ||
                                !task.canResume
                          ? null
                          : _run,
                    ),
                  ),
                ],
              ),
              if (task.error != null || _error != null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _error ?? task.error!,
                    style: TextStyle(color: IosColors.destructive),
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
                    subtitle: task.steps.isEmpty
                        ? null
                        : agentToolLabel(task.steps.last['name'] as String),
                    onTap: () => setState(() => _showSteps = !_showSteps),
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
                                'running' => _running ? 'i18n.agent_running' : 'i18n.agent_interrupted',
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
