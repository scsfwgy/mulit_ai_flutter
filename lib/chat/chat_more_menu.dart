import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

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
        title: Text(T('i18n.more')),
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
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.models),
            child: Text(T('i18n.model_settings')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.voice),
            child: Text(T('i18n.voice_services')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ChatMoreAction.search),
            child: Text(T('i18n.web_search')),
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
    label: T('i18n.more'),
    button: true,
    child: IosNavButton(
      icon: CupertinoIcons.ellipsis,
      onPressed: () => _show(context),
    ),
  );
}
