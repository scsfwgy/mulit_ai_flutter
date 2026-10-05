import 'package:flutter/cupertino.dart';

import 'app_preferences.dart';
import 'ios_style.dart';

enum ChatMoreAction { newTopic, model, messages, models, voice, search }

class ChatMoreButton extends StatelessWidget {
  const ChatMoreButton({
    super.key,
    required this.onNewTopic,
    required this.onModel,
    required this.onModelSettings,
    required this.onVoiceSettings,
    required this.onSearch,
    required this.onMessageSettings,
  });

  final VoidCallback onNewTopic;
  final VoidCallback onModel;
  final VoidCallback onModelSettings;
  final VoidCallback onVoiceSettings;
  final VoidCallback onSearch;
  final VoidCallback onMessageSettings;

  Future<void> _show(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final action = await showAppModalPopup<ChatMoreAction>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('更多')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.newTopic),
            child: Text(tr('新对话')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.model),
            child: Text(tr('切换模型')),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.messages),
            child: Text(tr('消息设置')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.models),
            child: Text(tr('模型设置')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.voice),
            child: Text(tr('语音服务')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.search),
            child: Text(tr('联网搜索')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case ChatMoreAction.newTopic:
        onNewTopic();
      case ChatMoreAction.model:
        onModel();
      case ChatMoreAction.models:
        onModelSettings();
      case ChatMoreAction.voice:
        onVoiceSettings();
      case ChatMoreAction.search:
        onSearch();
      case ChatMoreAction.messages:
        onMessageSettings();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr('更多'),
    button: true,
    child: IosNavButton(
      icon: CupertinoIcons.ellipsis,
      onPressed: () => _show(context),
    ),
  );
}
