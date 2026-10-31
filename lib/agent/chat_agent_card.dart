import 'package:flutter/cupertino.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/agent_screen.dart';
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
    this.onOpenChat,
    this.retryWithCurrentModel = false,
  });
  final AgentTask task;
  final bool running;
  final VoidCallback onDetails;
  final VoidCallback? onResume;
  final VoidCallback? onPause;
  final ValueChanged<AgentChatRequest>? onOpenChat;
  final bool retryWithCurrentModel;

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
                  '${T('i18n.agent_title')} · ${running ? agentActivity(task) : agentStatus(task)}',
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
          if (task.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                task.error!,
                style: TextStyle(color: IosColors.destructive, fontSize: 13),
              ),
            ),
          if (running && onPause != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: Size.zero,
              onPressed: onPause,
              child: Text(T('i18n.agent_pause')),
            ),
          if (!running)
            AgentTaskActions(
              key: ValueKey(task.id),
              task: task,
              onResume: onResume,
              onOpenChat: onOpenChat,
              retryWithCurrentModel: retryWithCurrentModel,
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
