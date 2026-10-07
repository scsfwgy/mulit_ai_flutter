import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// 聊天页底部输入区：语音/文字切换、按住说话与发送按钮。
///
/// 录音手势与发送流程仍由聊天页状态机持有，本组件只负责渲染与转发回调。
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.voiceMode,
    required this.transcribing,
    required this.voicePointerDown,
    required this.sending,
    required this.starting,
    required this.recording,
    required this.hasProviders,
    required this.onToggleVoiceMode,
    required this.onVoiceDown,
    required this.onVoiceMove,
    required this.onVoiceUp,
    required this.onVoiceCancel,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool voiceMode;
  final bool transcribing;
  final bool voicePointerDown;
  final bool sending;
  final bool starting;
  final bool recording;
  final bool hasProviders;
  final VoidCallback onToggleVoiceMode;
  final void Function(PointerDownEvent event) onVoiceDown;
  final void Function(PointerMoveEvent event) onVoiceMove;
  final void Function(PointerUpEvent event) onVoiceUp;
  final void Function(PointerCancelEvent event) onVoiceCancel;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: IosColors.chatChrome,
      border: Border(top: BorderSide(color: IosColors.separator, width: .5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(46, 44),
            onPressed: transcribing ? null : onToggleVoiceMode,
            child: Icon(
              voiceMode ? CupertinoIcons.keyboard : CupertinoIcons.mic,
              color: transcribing ? IosColors.secondary : IosColors.blue,
              size: 27,
              semanticLabel: T(voiceMode ? 'i18n.switch_to_text_input' : 'i18n.switch_to_voice_input'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: voiceMode
                ? Semantics(
                    button: true,
                    enabled: !transcribing,
                    label: transcribing
                        ? T('i18n.transcribing')
                        : T('i18n.hold_to_speak_release'),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: transcribing ? null : onVoiceDown,
                      onPointerMove: transcribing ? null : onVoiceMove,
                      onPointerUp: transcribing ? null : onVoiceUp,
                      onPointerCancel: transcribing ? null : onVoiceCancel,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: voicePointerDown
                              ? IosColors.blue.withValues(alpha: .22)
                              : IosColors.assistant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: IosColors.separator),
                        ),
                        child: Text(
                          T(transcribing ? 'i18n.transcribing' : 'i18n.hold_to_talk'),
                          style: TextStyle(
                            color: transcribing
                                ? IosColors.secondary
                                : IosColors.label,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                : CupertinoTextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: isDesktopApp
                        ? TextInputAction.newline
                        : TextInputAction.send,
                    onSubmitted: isDesktopApp ? null : (_) => onSend(),
                    textCapitalization: TextCapitalization.sentences,
                    placeholder: !hasProviders
                        ? T('i18n.add_a_model_service_first')
                        : T(isDesktopApp ? 'i18n.message_shift_enter' : 'i18n.message'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: IosColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: IosColors.separator),
                    ),
                  ),
          ),
          if (!voiceMode || sending) ...[
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              onPressed: sending
                  ? onStop
                  : (starting || recording || transcribing ? null : onSend),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: sending
                      ? IosColors.destructive
                      : starting
                      ? IosColors.secondary
                      : IosColors.blue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  sending ? CupertinoIcons.stop_fill : CupertinoIcons.arrow_up,
                  color: IosColors.onAccent,
                  size: 21,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
