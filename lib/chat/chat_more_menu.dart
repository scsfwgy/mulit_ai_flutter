import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/desktop_popup_menu.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

enum ChatMoreAction { newTopic, model, project, messages, settings }

class ChatMoreButton extends StatelessWidget {
  const ChatMoreButton({
    super.key,
    required this.onNewTopic,
    this.onProject,
    this.projectAssigned = false,
    required this.onModel,
    required this.onSettings,
    required this.onMessageSettings,
  });
  final VoidCallback onNewTopic;
  final VoidCallback? onProject;
  final bool projectAssigned;
  final VoidCallback onModel;
  final VoidCallback onSettings;
  final VoidCallback onMessageSettings;

  Future<void> _show(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final entries = [
      DesktopPopupEntry(
        ChatMoreAction.newTopic,
        T('i18n.new_chat'),
        CupertinoIcons.square_pencil,
      ),
      DesktopPopupEntry(
        ChatMoreAction.model,
        T('i18n.switch_model'),
        CupertinoIcons.arrow_2_circlepath,
      ),
      if (onProject != null)
        DesktopPopupEntry(
          ChatMoreAction.project,
          T(projectAssigned ? 'i18n.move_to_project' : 'i18n.add_to_project'),
          CupertinoIcons.folder,
        ),
      DesktopPopupEntry(
        ChatMoreAction.messages,
        T('i18n.message_settings'),
        CupertinoIcons.chat_bubble_text,
      ),
      DesktopPopupEntry(
        ChatMoreAction.settings,
        T('i18n.settings'),
        CupertinoIcons.gear,
      ),
    ];
    final action = isDesktopApp
        ? await showDesktopPopupMenu(context: context, entries: entries)
        : await showAppModalPopup<ChatMoreAction>(
            context: context,
            builder: (sheetContext) => CupertinoActionSheet(
              actions: [
                for (final entry in entries)
                  CupertinoActionSheetAction(
                    onPressed: () => Navigator.pop(sheetContext, entry.value),
                    child: Text(entry.label),
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
      case ChatMoreAction.project:
        onProject?.call();
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
    child: Builder(
      builder: (buttonContext) => IosNavButton(
        icon: CupertinoIcons.ellipsis,
        onPressed: () => _show(buttonContext),
      ),
    ),
  );
}
