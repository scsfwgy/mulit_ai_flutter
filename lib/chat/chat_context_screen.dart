import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
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
          content: Text(tr('无法保存上下文设置，请重试。')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('好')),
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
      title: '上下文设置',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: '上下文预算',
            footer:
                '预算包含提示词、历史消息与搜索内容，默认预留 4K Token 用于回复。Token 数为本机估算，请按模型实际限制调整。',
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
          const IosSection(
            footer:
                '超出预算时，发送最近的完整对话轮次，不删除本机历史。当前消息、提示词与搜索内容不会被静默截断。此设置适用于手机与桌面聊天。',
            children: [IosRow(title: '保留最近完整轮次', chevron: false)],
          ),
        ],
      ),
    ),
  );
}
