import 'package:flutter/cupertino.dart';
import 'package:mulit_ai_flutter/agent/agent_presentation.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/settings/purchase_screen.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// One recovery action at a time, shared by the chat card and task details.
class AgentTaskActions extends StatefulWidget {
  const AgentTaskActions({
    super.key,
    required this.task,
    this.onResume,
    this.onOpenChat,
    this.onOpenSettings,
    this.retryWithCurrentModel = false,
  });
  final AgentTask task;
  final VoidCallback? onResume;
  final ValueChanged<AgentChatRequest>? onOpenChat;
  final Future<AgentChatRequest?> Function()? onOpenSettings;
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
          final target = await widget.onOpenSettings?.call();
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

  Future<void> _refine() async {
    final text = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => const _AgentInstructionDialog(),
    );
    if (text == null ||
        !mounted ||
        AgentRunner.isBusy ||
        !widget.task.canResume) {
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await AgentStore().refine(widget.task, text);
      if (mounted) widget.onResume?.call();
    } on FormatException catch (e) {
      if (mounted) _error = e.message;
    } on StateError catch (e) {
      if (mounted) _error = T(e.message);
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
            (action != AgentRecoveryAction.settings ||
                widget.onOpenSettings != null) &&
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
            if (widget.onResume != null &&
                !widget.retryWithCurrentModel &&
                AppPreferences.instance.agentEnabled)
              CupertinoButton(
                key: const Key('agent-refine'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                minimumSize: Size.zero,
                onPressed: !_opening && !AgentRunner.isBusy ? _refine : null,
                child: Text(T('i18n.agent_refine')),
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

class _AgentInstructionDialog extends StatefulWidget {
  const _AgentInstructionDialog();
  @override
  State<_AgentInstructionDialog> createState() =>
      _AgentInstructionDialogState();
}

class _AgentInstructionDialogState extends State<_AgentInstructionDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: Text(T('i18n.agent_refine')),
    content: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CupertinoTextField(
        key: const Key('agent-refine-input'),
        controller: _input,
        autofocus: true,
        maxLength: 4000,
        minLines: 3,
        maxLines: 6,
        placeholder: T('i18n.agent_refine_hint'),
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: Text(T('i18n.cancel')),
      ),
      CupertinoDialogAction(
        onPressed: () {
          if (_input.text.trim().isNotEmpty) {
            Navigator.pop(context, _input.text.trim());
          }
        },
        child: Text(T('i18n.agent_refine_resume')),
      ),
    ],
  );
}
