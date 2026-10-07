import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/provider/provider_badge.dart';

class ChatModelTitle extends StatelessWidget {
  const ChatModelTitle({
    super.key,
    required this.label,
    required this.onPressed,
    this.providerName,
    this.providerPresetId,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? providerName;
  final String? providerPresetId;

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      color: IosColors.label,
      fontSize: 17,
      fontWeight: FontWeight.w600,
    );
    if (onPressed == null) {
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
    }
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .62,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (providerName != null) ...[
              ProviderBadge(
                name: providerName!,
                presetId: providerPresetId,
                size: 23,
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_down,
              color: IosColors.secondary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
