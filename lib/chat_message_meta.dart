import 'package:flutter/cupertino.dart';

import 'app_preferences.dart';
import 'ios_style.dart';
import 'message_copy.dart';
import 'provider_badge.dart';

class ChatMessageMeta extends StatelessWidget {
  const ChatMessageMeta({
    super.key,
    required this.assistant,
    required this.content,
    this.modelId,
    this.providerName,
    this.providerPresetId,
    this.firstTokenMs,
    this.totalMs,
    this.inputTokens,
    this.outputTokens,
    this.onCopy,
    this.onSpeak,
  });

  final bool assistant;
  final String content;
  final String? modelId;
  final String? providerName;
  final String? providerPresetId;
  final int? firstTokenMs;
  final int? totalMs;
  final int? inputTokens;
  final int? outputTokens;
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;

  String _time(int? milliseconds) {
    if (milliseconds == null) return '—';
    if (milliseconds < 1000) return '${milliseconds}ms';
    return '${(milliseconds / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    final parts = <String>[
      if (assistant &&
          firstTokenMs != null &&
          preferences.showChatInfo(ChatInfoField.firstFrame))
        '${tr('首帧')} ${_time(firstTokenMs)}',
      if (assistant &&
          totalMs != null &&
          preferences.showChatInfo(ChatInfoField.totalTime))
        '${tr('耗时')} ${_time(totalMs)}',
      if (assistant && preferences.showChatInfo(ChatInfoField.tokens)) ...[
        if (inputTokens != null || outputTokens != null) ...[
          '${tr('输入')} ${inputTokens ?? '—'}',
          '${tr('输出')} ${outputTokens ?? '—'}',
        ] else if (modelId != null)
          'Token —',
      ],
      if (preferences.showChatInfo(ChatInfoField.characters))
        '${visibleCharacterCount(assistant ? readableMarkdown(content) : content)} ${tr('字')}',
    ];
    final showModel =
        modelId != null && preferences.showChatInfo(ChatInfoField.modelId);
    if (providerName == null && !showModel && parts.isEmpty && onCopy == null) {
      return const SizedBox.shrink();
    }
    final style = TextStyle(
      color: IosColors.secondary,
      fontSize: 11,
      height: 1.2,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: assistant ? WrapAlignment.start : WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 9,
        runSpacing: 0,
        children: [
          if (providerName != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .62,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProviderBadge(
                    name: providerName!,
                    presetId: providerPresetId,
                    size: 17,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      providerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        color: IosColors.label.withValues(alpha: .75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showModel)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .7,
              ),
              child: Text(
                modelId!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  color: IosColors.label.withValues(alpha: .75),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          for (final part in parts) Text(part, style: style),
          if (onCopy != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 32),
              onPressed: onCopy,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: IosColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: IosColors.separator, width: .5),
                ),
                child: SizedBox(
                  width: 27,
                  height: 25,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.doc_on_doc,
                      size: 14,
                      color: IosColors.secondary,
                      semanticLabel: tr('复制消息'),
                    ),
                  ),
                ),
              ),
            ),
          if (assistant && onSpeak != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 32),
              onPressed: onSpeak,
              child: Icon(
                CupertinoIcons.speaker_2,
                size: 17,
                color: IosColors.secondary,
                semanticLabel: tr('朗读回复'),
              ),
            ),
        ],
      ),
    );
  }
}
