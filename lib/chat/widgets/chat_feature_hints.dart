import 'package:flutter/cupertino.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// Quiet indicators for capabilities that apply to the current conversation.
class ChatFeatureHints extends StatelessWidget {
  const ChatFeatureHints({
    super.key,
    required this.search,
    required this.readAloud,
    required this.agent,
    required this.memory,
  });
  final bool search;
  final bool readAloud;
  final bool agent;
  final bool memory;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      if (search) (CupertinoIcons.globe, 'i18n.chat_hint_search'),
      if (readAloud) (CupertinoIcons.speaker_2, 'i18n.chat_hint_read_aloud'),
      if (agent) (CupertinoIcons.sparkles, 'i18n.agent_title'),
      if (memory)
        (CupertinoIcons.bubble_left_bubble_right, 'i18n.chat_hint_memory'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final color = IosColors.secondary;
    return Padding(
      key: const Key('chat-feature-hints'),
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 12,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (icon, label) in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: 12, color: color),
                  const SizedBox(width: 3),
                  Text(
                    T(label),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1,
                      leadingDistribution: TextLeadingDistribution.even,
                      color: color,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
