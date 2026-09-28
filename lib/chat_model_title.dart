import 'package:flutter/cupertino.dart';

import 'ios_style.dart';

class ChatModelTitle extends StatelessWidget {
  const ChatModelTitle({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

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
