import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'app_platform.dart';
import 'app_preferences.dart';
import 'ios_style.dart';

enum DesktopSection {
  chat,
  providers,
  prompts,
  voice,
  search,
  messages,
  privacy,
  about,
  settings,
}

class DesktopNavigationMenu extends StatelessWidget {
  const DesktopNavigationMenu({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final DesktopSection selected;
  final ValueChanged<DesktopSection> onSelect;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        SizedBox(
          height: 56,
          child: Center(
            child: Text(
              tr('设置'),
              style: TextStyle(
                color: IosColors.label,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Divider(height: .5, color: IosColors.separator),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            children: [
              for (final item in [
                (DesktopSection.settings, CupertinoIcons.gear, '通用设置'),
                (DesktopSection.providers, CupertinoIcons.square_stack, '模型服务'),
                (DesktopSection.prompts, CupertinoIcons.text_quote, '提示词'),
                (DesktopSection.voice, CupertinoIcons.waveform, '语音服务'),
                (DesktopSection.search, CupertinoIcons.search, '联网搜索'),
                (DesktopSection.messages, CupertinoIcons.info, '消息设置'),
                (DesktopSection.privacy, CupertinoIcons.lock, '数据与隐私'),
                (DesktopSection.about, CupertinoIcons.info_circle, '关于'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected == item.$1
                          ? IosColors.blue.withValues(alpha: .14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CupertinoButton(
                      key: ValueKey('desktop-section-${item.$1.name}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      onPressed: () => onSelect(item.$1),
                      child: Row(
                        children: [
                          Icon(
                            item.$2,
                            size: 19,
                            color: selected == item.$1
                                ? IosColors.blue
                                : IosColors.secondary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            tr(item.$3),
                            style: TextStyle(
                              fontSize: 14,
                              color: selected == item.$1
                                  ? IosColors.blue
                                  : IosColors.label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: .5, color: IosColors.separator),
        SizedBox(
          height: 62,
          child: CupertinoButton(
            key: const ValueKey('desktop-section-chat'),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            onPressed: () => onSelect(DesktopSection.chat),
            child: Row(
              children: [
                Icon(CupertinoIcons.back, color: IosColors.blue, size: 22),
                const SizedBox(width: 8),
                Text(tr('返回聊天'), style: TextStyle(color: IosColors.blue)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class DesktopNavigationObserver extends NavigatorObserver {
  DesktopNavigationObserver(this.onChat);
  final VoidCallback onChat;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.isFirst == true) onChat();
  }
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
        // A nested route's modal barrier must not hide the sibling menu from VoiceOver.
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
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): onNew,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): onSettings,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
            inputFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): send,
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
