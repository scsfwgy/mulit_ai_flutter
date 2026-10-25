import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// macOS 用 Command。Windows 与 Linux 用 Control，和系统菜单习惯一致。
bool desktopUsesControlShortcuts(TargetPlatform platform) =>
    platform == TargetPlatform.windows || platform == TargetPlatform.linux;

SingleActivator desktopCommandActivator(LogicalKeyboardKey key) {
  final control = desktopUsesControlShortcuts(defaultTargetPlatform);
  return SingleActivator(key, control: control, meta: !control);
}

/// Keeps the existing chat route and sidebar callbacks across window resizes.
class DesktopChatLayout extends StatelessWidget {
  const DesktopChatLayout({
    super.key,
    required this.sidebar,
    required this.chat,
    required this.showSidebar,
  });

  final Widget sidebar;
  final Widget chat;
  final bool showSidebar;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (showSidebar) ...[
        SizedBox(
          width: 280,
          child: Material(color: IosColors.background, child: sidebar),
        ),
        VerticalDivider(width: 1, thickness: .5, color: IosColors.separator),
      ],
      Expanded(
        key: const ValueKey('desktop-chat-content'),
        // A nested route's modal barrier must not hide the sibling topic list from VoiceOver.
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: chat,
        ),
      ),
    ],
  );
}

/// Enter sends only committed text; IME confirmation remains with the editor.
class DesktopChatKeyboard extends StatelessWidget {
  const DesktopChatKeyboard({
    super.key,
    required this.controller,
    required this.inputFocus,
    required this.onSend,
    required this.onNew,
    required this.onSettings,
    required this.child,
  });

  final TextEditingController controller;
  final FocusNode inputFocus;
  final VoidCallback onSend;
  final VoidCallback onNew;
  final VoidCallback onSettings;
  final Widget child;

  bool get _composing =>
      controller.value.composing.isValid &&
      !controller.value.composing.isCollapsed;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopApp) return child;
    void send() {
      if (!_composing) onSend();
    }

    return CallbackShortcuts(
      bindings: {
        desktopCommandActivator(LogicalKeyboardKey.keyN): onNew,
        desktopCommandActivator(LogicalKeyboardKey.comma): onSettings,
        desktopCommandActivator(LogicalKeyboardKey.keyL):
            inputFocus.requestFocus,
        desktopCommandActivator(LogicalKeyboardKey.enter): send,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          final keyboard = HardwareKeyboard.instance;
          if (inputFocus.hasFocus &&
              event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
              !keyboard.isShiftPressed &&
              !keyboard.isMetaPressed &&
              !keyboard.isControlPressed &&
              !keyboard.isAltPressed &&
              !_composing) {
            send();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}
