import 'package:flutter/cupertino.dart';

import 'app_preferences.dart';
import 'ios_style.dart';

enum ChatMoreAction { newTopic, model, providers }

class ChatMoreButton extends StatelessWidget {
  const ChatMoreButton({
    super.key,
    required this.onNewTopic,
    required this.onModel,
    required this.onProviders,
    required this.canChangeModel,
  });

  final VoidCallback onNewTopic;
  final VoidCallback onModel;
  final VoidCallback onProviders;
  final bool canChangeModel;

  Future<void> _show(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final action = await showCupertinoModalPopup<ChatMoreAction>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('更多')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.newTopic),
            child: Text(tr('新对话')),
          ),
          if (canChangeModel)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(sheetContext, ChatMoreAction.model),
              child: Text(tr('切换模型')),
            ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.providers),
            child: Text(tr('模型服务')),
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
      case ChatMoreAction.providers:
        onProviders();
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
