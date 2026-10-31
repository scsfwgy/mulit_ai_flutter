import 'package:flutter/cupertino.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/agent_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class ChatAgentCard extends StatelessWidget {
  const ChatAgentCard({
    super.key,
    required this.task,
    required this.running,
    required this.onDetails,
    this.onResume,
    this.onPause,
  });
  final AgentTask task;
  final bool running;
  final VoidCallback onDetails;
  final VoidCallback? onResume;
  final VoidCallback? onPause;

  Future<void> _file(
    BuildContext context,
    Map<String, dynamic> artifact,
    bool share,
  ) async {
    try {
      await openAgentArtifact(context, task, artifact, share: share);
    } catch (_) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          content: Text(T('i18n.attachment_unavailable')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(T('i18n.ok')),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('chat-agent-${task.userMessageId}'),
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: IosColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: IosColors.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (running)
                const CupertinoActivityIndicator()
              else
                Icon(CupertinoIcons.sparkles, color: IosColors.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${T('i18n.agent_title')} · ${agentStatus(task)}',
                  style: TextStyle(
                    color: IosColors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(4),
                minimumSize: Size.zero,
                onPressed: onDetails,
                child: Text(
                  T('i18n.agent_steps'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          Text(
            F('i18n.agent_progress', [task.rounds, task.calls]),
            style: TextStyle(color: IosColors.secondary, fontSize: 12),
          ),
          if (task.steps.isNotEmpty && running)
            Text(
              agentToolLabel(task.steps.last['name'] as String),
              style: TextStyle(color: IosColors.secondary, fontSize: 13),
            ),
          if (task.contextTokens > 0)
            Text(
              F('i18n.agent_context_usage', [
                task.contextTokens,
                task.contextWindowTokens,
              ]),
              style: TextStyle(color: IosColors.secondary, fontSize: 12),
            ),
          if (task.contextCompacted)
            Text(
              T('i18n.agent_context_compacted'),
              style: TextStyle(color: IosColors.secondary, fontSize: 12),
            ),
          if (task.finishNotice != null)
            Text(
              T(
                task.finishNotice == 'loop'
                    ? 'i18n.agent_loop_notice'
                    : 'i18n.agent_budget_notice',
              ),
              style: TextStyle(color: IosColors.secondary, fontSize: 12),
            ),
          if (task.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                task.error!,
                style: TextStyle(color: IosColors.destructive, fontSize: 13),
              ),
            ),
          if (task.contextBlocked)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: Size.zero,
              onPressed: () => Navigator.push<void>(
                context,
                appPageRoute(
                  builder: (_) => const ChatContextScreen(forAgent: true),
                ),
              ),
              child: Text(T('i18n.agent_adjust_context')),
            ),
          if (running && onPause != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: Size.zero,
              onPressed: onPause,
              child: Text(T('i18n.agent_pause')),
            ),
          if (!running && onResume != null && task.canResume)
            AnimatedBuilder(
              animation: AppPreferences.instance,
              builder: (context, _) => CupertinoButton(
                key: const Key('chat-agent-resume'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                minimumSize: Size.zero,
                onPressed: AppPreferences.instance.agentEnabled
                    ? onResume
                    : null,
                child: Text(T('i18n.agent_resume')),
              ),
            ),
          for (final artifact in task.artifacts)
            Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.centerLeft,
                    onPressed: () => _file(context, artifact, false),
                    child: Text(
                      artifact['name'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => _file(context, artifact, true),
                  child: const Icon(CupertinoIcons.share, size: 20),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
