import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class ChatContextScreen extends StatefulWidget {
  const ChatContextScreen({super.key});

  @override
  State<ChatContextScreen> createState() => _ChatContextScreenState();
}

class _ChatContextScreenState extends State<ChatContextScreen> {
  bool _saving = false;

  Future<void> _select(int value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AppPreferences.instance.setContextWindowTokens(value);
    } catch (_) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          content: Text(T('i18n.could_not_save_context_settings')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(T('i18n.ok')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.context_settings'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: T('i18n.context_budget'),
            footer:
                T('i18n.the_budget_includes_prompts_history'),
            children: [
              for (final tokens in ChatContext.windowOptions)
                IosRow(
                  title: '${tokens ~/ 1024}K Token',
                  chevron: false,
                  trailing:
                      tokens == AppPreferences.instance.contextWindowTokens
                      ? Icon(CupertinoIcons.check_mark, color: IosColors.blue)
                      : const SizedBox.shrink(),
                  onTap: _saving ? null : () => _select(tokens),
                ),
            ],
          ),
          IosSection(
            footer:
                T('i18n.when_over_budget_send_recent'),
            children: [IosRow(title: T('i18n.keep_recent_complete_turns'), chevron: false)],
          ),
        ],
      ),
    ),
  );
}
