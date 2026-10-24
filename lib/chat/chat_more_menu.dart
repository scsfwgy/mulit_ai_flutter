import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

enum ChatMoreAction { newTopic, model, messages, settings }

class ChatMoreButton extends StatelessWidget {
  const ChatMoreButton({
    super.key,
    required this.onNewTopic,
    required this.onModel,
    required this.onSettings,
    required this.onMessageSettings,
  });

  final VoidCallback onNewTopic;
  final VoidCallback onModel;
  final VoidCallback onSettings;
  final VoidCallback onMessageSettings;

  Future<void> _show(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final action = await showAppModalPopup<ChatMoreAction>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.newTopic),
            child: Text(T('i18n.new_chat')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.model),
            child: Text(T('i18n.switch_model')),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.messages),
            child: Text(T('i18n.message_settings')),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, ChatMoreAction.settings),
            child: Text(T('i18n.settings')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case ChatMoreAction.newTopic:
        onNewTopic();
      case ChatMoreAction.model:
        onModel();
      case ChatMoreAction.messages:
        onMessageSettings();
      case ChatMoreAction.settings:
        onSettings();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: T('i18n.more'),
    button: true,
    child: IosNavButton(
      icon: CupertinoIcons.ellipsis,
      onPressed: () => _show(context),
    ),
  );
}
