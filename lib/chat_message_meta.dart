import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'ios_style.dart';
import 'message_copy.dart';

class ChatMessageMeta extends StatelessWidget {
  const ChatMessageMeta({
    super.key,
    required this.assistant,
    required this.content,
    this.modelId,
    this.firstTokenMs,
    this.totalMs,
    this.inputTokens,
    this.outputTokens,
  });

  final bool assistant;
  final String content;
  final String? modelId;
  final int? firstTokenMs;
  final int? totalMs;
  final int? inputTokens;
  final int? outputTokens;

  String _time(int? milliseconds) {
    if (milliseconds == null) return '—';
    if (milliseconds < 1000) return '${milliseconds}ms';
    return '${(milliseconds / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    final parts = <String>[
      if (assistant && preferences.showChatInfo(ChatInfoField.firstFrame))
        '${tr('首帧')} ${_time(firstTokenMs)}',
      if (assistant && preferences.showChatInfo(ChatInfoField.totalTime))
        '${tr('总耗时')} ${_time(totalMs)}',
      if (assistant && preferences.showChatInfo(ChatInfoField.tokens)) ...[
        '${tr('输入')} ${inputTokens ?? '—'}',
        '${tr('输出')} ${outputTokens ?? '—'}',
      ],
      if (preferences.showChatInfo(ChatInfoField.characters))
        '${tr('字数')} ${visibleCharacterCount(assistant ? readableMarkdown(content) : content)}',
    ];
    final showModel = preferences.showChatInfo(ChatInfoField.modelId);
    if (!showModel && parts.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(color: IosColors.secondary, fontSize: 11);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: assistant
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          if (showModel)
            Text(
              '${tr('模型 ID')} ${modelId ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          if (parts.isNotEmpty)
            Wrap(
              alignment: assistant ? WrapAlignment.start : WrapAlignment.end,
              spacing: 9,
              runSpacing: 2,
              children: [for (final part in parts) Text(part, style: style)],
            ),
        ],
      ),
    );
  }
}
