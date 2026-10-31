import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_attachments.dart';
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
    this.attachments = const [],
    this.pickingAttachment = false,
    this.onAddAttachment,
    this.onRemoveAttachment,
    this.featureHints,
    this.inputEnabled = true,
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
  final List<ChatAttachment> attachments;
  final bool pickingAttachment;
  final VoidCallback? onAddAttachment;
  final ValueChanged<ChatAttachment>? onRemoveAttachment;
  final Widget? featureHints;
  final bool inputEnabled;

  bool get _busy => starting || recording || transcribing || pickingAttachment;

  Widget _attachmentButton() => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: sending || _busy ? null : onAddAttachment,
    child: pickingAttachment
        ? const CupertinoActivityIndicator()
        : Icon(
            CupertinoIcons.add_circled,
            size: 27,
            color: IosColors.blue,
            semanticLabel: T('i18n.attachment_add'),
          ),
  );

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: IosColors.chatChrome,
      border: Border(top: BorderSide(color: IosColors.separator, width: .5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attachments.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 124),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChatAttachments(
                      attachments: attachments,
                      onRemove: starting || pickingAttachment
                          ? null
                          : onRemoveAttachment,
                    ),
                    const SizedBox(width: 8),
                    _attachmentButton(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                T('i18n.attachment_send_notice'),
                style: TextStyle(color: IosColors.secondary, fontSize: 11),
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(46, 44),
                onPressed: transcribing || !inputEnabled
                    ? null
                    : onToggleVoiceMode,
                child: Icon(
                  voiceMode ? CupertinoIcons.keyboard : CupertinoIcons.mic,
                  color: transcribing ? IosColors.secondary : IosColors.blue,
                  size: 27,
                  semanticLabel: T(
                    voiceMode
                        ? 'i18n.switch_to_text_input'
                        : 'i18n.switch_to_voice_input',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: voiceMode
                    ? Semantics(
                        button: true,
                        enabled: inputEnabled && !transcribing,
                        label: transcribing
                            ? T('i18n.transcribing')
                            : T('i18n.hold_to_speak_release'),
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: transcribing || !inputEnabled
                              ? null
                              : onVoiceDown,
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
                              T(
                                transcribing
                                    ? 'i18n.transcribing'
                                    : 'i18n.hold_to_talk',
                              ),
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
                        enabled: inputEnabled && (!starting || sending),
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
                            : T(
                                isDesktopApp
                                    ? 'i18n.message_shift_enter'
                                    : 'i18n.message',
                              ),
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
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasContent =
                      (!voiceMode && value.text.trim().isNotEmpty) ||
                      attachments.isNotEmpty;
                  if (!sending && !hasContent) return _attachmentButton();
                  return CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(56, 44),
                    color: sending ? IosColors.destructive : IosColors.blue,
                    disabledColor: IosColors.secondary,
                    borderRadius: BorderRadius.circular(6),
                    onPressed: sending ? onStop : (_busy ? null : onSend),
                    child: sending
                        ? Icon(
                            CupertinoIcons.stop_fill,
                            semanticLabel: T('i18n.stop_generation'),
                            color: IosColors.onAccent,
                            size: 21,
                          )
                        : Text(
                            T('i18n.send'),
                            style: TextStyle(
                              color: IosColors.onAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  );
                },
              ),
            ],
          ),
          ?featureHints,
        ],
      ),
    ),
  );
}
