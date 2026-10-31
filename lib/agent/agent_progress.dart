import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:mulit_ai_flutter/agent/agent_presentation.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/agent_tools.dart';
import 'package:mulit_ai_flutter/chat/chat_loading_status.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// Shows recorded tool activity; it never invents steps while a model is pending.
class AgentProgress extends StatefulWidget {
  const AgentProgress({
    super.key,
    required this.task,
    required this.running,
    this.elapsedMilliseconds,
  });
  final AgentTask task;
  final bool running;
  final ValueListenable<int>? elapsedMilliseconds;
  @override
  State<AgentProgress> createState() => _AgentProgressState();
}

class _AgentProgressState extends State<AgentProgress> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final steps = task.steps;
    final showRecent = widget.running || task.canResume;
    final recent = steps.where((step) => step['status'] != 'pending').toList();
    final visible = _expanded
        ? steps
        : showRecent
        ? recent.skip((recent.length - 3).clamp(0, recent.length))
        : const <Map<String, dynamic>>[];
    final request = task.requests.lastOrNull;
    final modelRunning =
        widget.running &&
        request?['status'] == 'running' &&
        task.pending.isEmpty &&
        !task.finalReady;
    final showActivity =
        widget.running &&
        (task.pending.isEmpty ||
            task.finalReady ||
            !steps.any((step) => step['status'] == 'running'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in visible)
          _ProgressRow(
            active: widget.running && step['status'] == 'running',
            icon: switch (step['status']) {
              'completed' => CupertinoIcons.check_mark_circled_solid,
              'failed' => CupertinoIcons.exclamationmark_circle,
              'running' => CupertinoIcons.pause_circle,
              'skipped' => CupertinoIcons.minus_circle,
              _ => CupertinoIcons.circle,
            },
            failed: step['status'] == 'failed',
            title:
                '${agentToolLabel(step['name'] as String)} · ${agentStepStatus(step, running: widget.running)}',
            detail: agentStepDetail(step),
          ),
        if (showActivity)
          _ProgressRow(
            active: true,
            icon: CupertinoIcons.circle,
            title: modelRunning && request?['round'] is int
                ? F('i18n.agent_round_activity', [
                    request!['round'],
                    agentActivity(task),
                  ])
                : agentActivity(task),
            detail: modelRunning && steps.isEmpty
                ? T('i18n.agent_waiting_steps')
                : null,
          ),
        if (steps.isNotEmpty && (!showRecent || steps.length > 3 || _expanded))
          CupertinoButton(
            key: const Key('agent-progress-toggle'),
            minimumSize: Size.zero,
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? T('i18n.agent_progress_collapse')
                  : F('i18n.agent_progress_expand', [steps.length]),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        if (widget.running && widget.elapsedMilliseconds != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ValueListenableBuilder<int>(
              valueListenable: widget.elapsedMilliseconds!,
              builder: (_, elapsed, _) => Text(
                F('i18n.agent_elapsed', [formatLoadingDuration(elapsed)]),
                style: TextStyle(
                  color: IosColors.secondary,
                  fontSize: 12,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.active,
    required this.icon,
    required this.title,
    this.detail,
    this.failed = false,
  });
  final bool active;
  final bool failed;
  final IconData icon;
  final String title;
  final String? detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: active
              ? const CupertinoActivityIndicator(radius: 7)
              : Icon(
                  icon,
                  size: 15,
                  color: failed ? IosColors.destructive : IosColors.secondary,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: failed ? IosColors.destructive : IosColors.label,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: IosColors.secondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
