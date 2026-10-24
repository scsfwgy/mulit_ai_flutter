import 'dart:io';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mulit_ai_flutter/chat/widgets/chat_attachments.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class LibraryDay {
  const LibraryDay(this.day, this.files);
  final DateTime day;
  final List<StoredChatFile> files;
}

List<LibraryDay> groupLibraryFiles(List<StoredChatFile> files) {
  final groups = <DateTime, List<StoredChatFile>>{};
  final order = <DateTime>[];
  for (final file in files) {
    final time = DateTime.fromMillisecondsSinceEpoch(file.createdAt);
    final day = DateTime(time.year, time.month, time.day);
    groups
        .putIfAbsent(day, () {
          order.add(day);
          return [];
        })
        .add(file);
  }
  return [for (final day in order) LibraryDay(day, groups[day]!)];
}

String libraryDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return T('i18n.today');
  if (day == today.subtract(const Duration(days: 1))) {
    return T('i18n.yesterday');
  }
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

String libraryShareName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\x00-\x1f/\\]'), '').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'file';
  return cleaned;
}

Future<void> shareStoredChatFile(StoredChatFile file, Rect? origin) async {
  final source = await AttachmentStore.instance.file(file.attachment);
  if (!await source.exists()) {
    throw const AttachmentException('i18n.attachment_unavailable');
  }
  final name = libraryShareName(file.attachment.name);
  final root = await getTemporaryDirectory();
  final folder = Directory(
    p.join(
      root.path,
      'shared-chat-files',
      '${file.messageId}-${file.attachment.fileName}',
    ),
  );
  await folder.create(recursive: true);
  final copy = File(p.join(folder.path, name));
  await source.copy(copy.path);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(copy.path, mimeType: file.attachment.mimeType, name: name),
        ],
        sharePositionOrigin: origin,
      ),
    );
  } on UnimplementedError {
    final location = await files.getSaveLocation(suggestedName: name);
    if (location == null) return;
    await source.copy(location.path);
  }
}

Future<void> revealStoredChatFile(StoredChatFile file) async {
  final source = await AttachmentStore.instance.file(file.attachment);
  if (!await source.exists()) {
    throw const AttachmentException('i18n.attachment_unavailable');
  }
  final code = await _revealInFileManager(source.path);
  // Explorer reports 1 even when the folder opens.
  if (code != 0 && !Platform.isWindows) {
    throw const AttachmentException('i18n.library_path_failed');
  }
}

Future<int> _revealInFileManager(String path) async {
  if (Platform.isMacOS) {
    return (await Process.run('open', ['-R', path])).exitCode;
  }
  if (Platform.isWindows) {
    return (await Process.run('explorer', ['/select,$path'])).exitCode;
  }
  return (await Process.run('xdg-open', [p.dirname(path)])).exitCode;
}

const libraryDesktopMenuKey = Key('library-desktop-menu');

Future<String?> showDesktopLibraryMenu({
  required BuildContext context,
  required Rect? anchor,
  required String title,
}) => showGeneralDialog<String>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: const Color(0x33000000),
  transitionDuration: Duration.zero,
  pageBuilder: (dialogContext, _, _) => DesktopLibraryMenu(
    anchor: anchor,
    title: title,
    onLocate: () => Navigator.pop(dialogContext, 'locate'),
    onShare: () => Navigator.pop(dialogContext, 'share'),
    onReveal: () => Navigator.pop(dialogContext, 'path'),
  ),
);

class DesktopLibraryMenu extends StatelessWidget {
  const DesktopLibraryMenu({
    super.key,
    required this.anchor,
    required this.title,
    required this.onLocate,
    required this.onShare,
    required this.onReveal,
  });

  static const width = 228.0;

  final Rect? anchor;
  final String title;
  final VoidCallback onLocate;
  final VoidCallback onShare;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      const estimatedHeight = 184.0;
      var left = anchor?.left ?? (size.width - width) / 2;
      var top = anchor == null
          ? (size.height - estimatedHeight) / 2
          : anchor!.bottom + 6;
      if (left + width > size.width - 16) left = size.width - width - 16;
      if (left < 16) left = 16;
      if (top + estimatedHeight > size.height - 16) {
        top = (anchor?.top ?? top) - estimatedHeight - 6;
      }
      if (top < 16) top = 16;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: DefaultTextStyle(
              style: const TextStyle(decoration: TextDecoration.none),
              child: DecoratedBox(
                key: libraryDesktopMenuKey,
                decoration: BoxDecoration(
                  color: IosColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: IosColors.separator),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: IosColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ColoredBox(
                        color: IosColors.separator,
                        child: const SizedBox(height: 1),
                      ),
                      _DesktopMenuRow(
                        icon: CupertinoIcons.location,
                        label: T('i18n.library_locate'),
                        onTap: onLocate,
                      ),
                      _DesktopMenuRow(
                        icon: CupertinoIcons.share,
                        label: T('i18n.share'),
                        onTap: onShare,
                      ),
                      _DesktopMenuRow(
                        icon: CupertinoIcons.folder,
                        label: T('i18n.library_file_path'),
                        onTap: onReveal,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _DesktopMenuRow extends StatefulWidget {
  const _DesktopMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_DesktopMenuRow> createState() => _DesktopMenuRowState();
}

class _DesktopMenuRowState extends State<_DesktopMenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: ColoredBox(
        color: _hover
            ? IosColors.blue.withValues(alpha: .12)
            : const Color(0x00000000),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: IosColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(color: IosColors.label, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ResourceLibraryScreen extends StatefulWidget {
  const ResourceLibraryScreen({
    super.key,
    this.loadFiles,
    this.shareFile,
    this.revealFile,
  });

  final Future<List<StoredChatFile>> Function()? loadFiles;
  final Future<void> Function(StoredChatFile file, Rect? origin)? shareFile;
  final Future<void> Function(StoredChatFile file)? revealFile;

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen> {
  List<LibraryDay>? _days;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final files =
          await (widget.loadFiles ?? ChatStore.instance.libraryFiles)();
      if (!mounted) return;
      setState(() => _days = groupLibraryFiles(files));
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(T(message), textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        backgroundColor: IosColors.label,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _actions(StoredChatFile file, BuildContext rowContext) async {
    final box = rowContext.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final action = isDesktopApp
        ? await showDesktopLibraryMenu(
            context: context,
            anchor: origin,
            title: file.attachment.name,
          )
        : await showAppModalPopup<String>(
            context: context,
            builder: (sheetContext) => CupertinoActionSheet(
              title: Text(file.attachment.name),
              actions: [
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(sheetContext, 'locate'),
                  child: Text(T('i18n.library_locate')),
                ),
                CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(sheetContext, 'share'),
                  child: Text(T('i18n.share')),
                ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(T('i18n.cancel')),
              ),
            ),
          );
    if (!mounted || action == null) return;
    if (action == 'locate') {
      Navigator.pop(context, file);
      return;
    }
    if (action == 'path') {
      try {
        await (widget.revealFile ?? revealStoredChatFile)(file);
      } on AttachmentException catch (error) {
        if (mounted) _notify(error.toString());
      } catch (_) {
        if (mounted) _notify(T('i18n.library_path_failed'));
      }
      return;
    }
    try {
      await (widget.shareFile ?? shareStoredChatFile)(file, origin);
    } on AttachmentException catch (error) {
      if (mounted) _notify(error.toString());
    } catch (_) {
      if (mounted) _notify(T('i18n.library_share_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    return Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: T('i18n.resource_library'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: days == null
            ? Center(
                child: _failed
                    ? Text(
                        T('i18n.attachment_unavailable'),
                        style: TextStyle(color: IosColors.secondary),
                      )
                    : const CupertinoActivityIndicator(),
              )
            : days.isEmpty
            ? Center(
                child: Text(
                  T('i18n.library_empty'),
                  style: TextStyle(color: IosColors.secondary, fontSize: 16),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: days.fold<int>(
                  0,
                  (count, day) => count + 1 + day.files.length,
                ),
                itemBuilder: (context, index) {
                  var cursor = index;
                  for (final day in days) {
                    if (cursor == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                        child: Text(
                          libraryDayLabel(
                            day.day,
                            DateTime.now(),
                          ).toUpperCase(),
                          style: TextStyle(
                            color: IosColors.secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }
                    cursor--;
                    if (cursor < day.files.length) {
                      final file = day.files[cursor];
                      return _LibraryFileRow(
                        file: file,
                        onPreview: () => Navigator.of(context).push(
                          appPageRoute<void>(
                            builder: (_) => ChatAttachmentPreview(
                              attachment: file.attachment,
                            ),
                          ),
                        ),
                        onActions: (rowContext) => _actions(file, rowContext),
                      );
                    }
                    cursor -= day.files.length;
                  }
                  return const SizedBox.shrink();
                },
              ),
      ),
    );
  }
}

class _LibraryFileRow extends StatelessWidget {
  const _LibraryFileRow({
    required this.file,
    required this.onPreview,
    required this.onActions,
  });

  final StoredChatFile file;
  final VoidCallback onPreview;
  final ValueChanged<BuildContext> onActions;

  @override
  Widget build(BuildContext context) {
    final attachment = file.attachment;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: attachment.isImage ? onPreview : null,
      onLongPress: () => onActions(context),
      onSecondaryTap: () => onActions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _thumb(attachment),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: IosColors.label, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.topicTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: IosColors.secondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(attachment.size / 1024).ceil()} KB',
              style: TextStyle(color: IosColors.secondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(ChatAttachment attachment) {
    if (!attachment.isImage) {
      return Icon(
        attachment.isPdf
            ? CupertinoIcons.doc_richtext
            : CupertinoIcons.doc_text,
        color: IosColors.blue,
        size: 28,
      );
    }
    return FutureBuilder<File>(
      future: AttachmentStore.instance.file(attachment),
      builder: (context, snapshot) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: snapshot.hasData
            ? Image.file(
                snapshot.data!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                cacheWidth: 128,
                errorBuilder: (_, _, _) => const Icon(CupertinoIcons.photo),
              )
            : const SizedBox(
                width: 44,
                height: 44,
                child: Icon(CupertinoIcons.photo),
              ),
      ),
    );
  }
}
