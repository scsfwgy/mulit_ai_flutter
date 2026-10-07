import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

String formatLoadingDuration(int milliseconds) {
  if (milliseconds < 1000) return '${milliseconds}ms';
  final seconds = milliseconds ~/ 1000;
  final remainder = (milliseconds % 1000).toString().padLeft(3, '0');
  return '${seconds}s ${remainder}ms';
}

class ChatLoadingStatus extends StatelessWidget {
  const ChatLoadingStatus({
    super.key,
    required this.elapsedMilliseconds,
    this.label = 'i18n.loading',
  });

  final ValueListenable<int> elapsedMilliseconds;
  final String label;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: elapsedMilliseconds,
    builder: (context, elapsed, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CupertinoActivityIndicator(radius: 7),
        const SizedBox(width: 8),
        Text(
          '${T(label)} · ${formatLoadingDuration(elapsed)}',
          style: TextStyle(
            color: IosColors.secondary,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
