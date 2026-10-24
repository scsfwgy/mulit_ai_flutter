import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class DesktopAttachmentDrop extends StatefulWidget {
  const DesktopAttachmentDrop({
    super.key,
    required this.enabled,
    required this.onDrop,
    required this.child,
  });
  final bool enabled;
  final Future<void> Function(List<DropItem>) onDrop;
  final Widget child;

  @override
  State<DesktopAttachmentDrop> createState() => _DesktopAttachmentDropState();
}

class _DesktopAttachmentDropState extends State<DesktopAttachmentDrop> {
  bool _hovering = false;

  void _setHovering(bool hovering) {
    if (!mounted || _hovering == hovering) return;
    // The plugin can emit exit while disabling its target during a rebuild.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _setHovering(hovering),
      );
      return;
    }
    setState(() => _hovering = hovering);
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: (details) {
        _setHovering(false);
        unawaited(widget.onDrop(details.files));
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (enabled && _hovering)
            IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: IosColors.surface.withValues(alpha: .94),
                  border: Border.all(color: IosColors.blue, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.doc_on_doc,
                      color: IosColors.blue,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      T('i18n.attachment_drop_here'),
                      style: TextStyle(color: IosColors.label, fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
