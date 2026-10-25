import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class DesktopPopupEntry<T> {
  const DesktopPopupEntry(
    this.value,
    this.label,
    this.icon, {
    this.destructive = false,
  });
  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

Future<T?> showDesktopPopupMenu<T>({
  required BuildContext context,
  required List<DesktopPopupEntry<T>> entries,
}) {
  final button = context.findRenderObject()! as RenderBox;
  final anchor = button.localToGlobal(Offset.zero) & button.size;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: CupertinoLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x00000000),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final width = math.min(224.0, size.width - 16);
        final height = math.min(entries.length * 40.0 + 8, size.height - 16);
        final left = (anchor.right - width).clamp(
          8.0,
          math.max(8.0, size.width - width - 8),
        );
        final below = anchor.bottom + 6;
        final top =
            (below + height > size.height - 8 ? anchor.top - height - 6 : below)
                .clamp(8.0, math.max(8.0, size.height - height - 8));
        return Stack(
          children: [
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              width: width,
              child: Focus(
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.pop(context);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: DecoratedBox(
                  key: const ValueKey('desktop-popup-menu'),
                  decoration: BoxDecoration(
                    color: IosColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: IosColors.separator, width: .5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 20,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: height),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final entry in entries)
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size(0, 40),
                                borderRadius: BorderRadius.zero,
                                onPressed: () =>
                                    Navigator.pop(context, entry.value),
                                child: Row(
                                  children: [
                                    Icon(
                                      entry.icon,
                                      size: 18,
                                      color: entry.destructive
                                          ? IosColors.destructive
                                          : IosColors.secondary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        entry.label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: entry.destructive
                                              ? IosColors.destructive
                                              : IosColors.label,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
