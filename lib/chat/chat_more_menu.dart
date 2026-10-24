import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

enum ChatMoreAction {
  newTopic,
  model,
  messages,
  models,
  voice,
  search,
  chatMemory,
  viewMemory,
}

class ChatMemoryMenuState {
  const ChatMemoryMenuState({required this.enabled, required this.used});

  final bool enabled;
  final bool used;
}

class ChatMoreButton extends StatelessWidget {
  const ChatMoreButton({
    super.key,
    required this.onNewTopic,
    required this.onModel,
    required this.onModelSettings,
    required this.onVoiceSettings,
    required this.onSearch,
    required this.onMessageSettings,
    this.memoryState,
    this.onToggleChatMemory,
    this.onViewMemory,
  });

  final VoidCallback onNewTopic;
  final VoidCallback onModel;
  final VoidCallback onModelSettings;
  final VoidCallback onVoiceSettings;
  final VoidCallback onSearch;
  final VoidCallback onMessageSettings;
  final Future<ChatMemoryMenuState> Function()? memoryState;
  final VoidCallback? onToggleChatMemory;
  final VoidCallback? onViewMemory;

  Future<void> _show(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final memory = await memoryState?.call();
    if (!context.mounted) return;
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
          if (memory != null && onToggleChatMemory != null)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(sheetContext, ChatMoreAction.chatMemory),
              child: Text(
                T(memory.used ? 'i18n.memory_chat_on' : 'i18n.memory_chat_off'),
              ),
            ),
          if (onViewMemory != null)
            CupertinoActionSheetAction(
              onPressed: () =>
                  Navigator.pop(sheetContext, ChatMoreAction.viewMemory),
              child: Text(T('i18n.memory_view')),
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
      case ChatMoreAction.chatMemory:
        onToggleChatMemory?.call();
      case ChatMoreAction.viewMemory:
        onViewMemory?.call();
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
