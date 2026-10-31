import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:mulit_ai_flutter/core/file_actions.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mulit_ai_flutter/agent/agent_artifact_format.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/chat/project_screen.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/desktop_popup_menu.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:share_plus/share_plus.dart';

Future<void> agentResultNotice(BuildContext context, String message) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(T('i18n.ok')),
          ),
        ],
      ),
    );

/// Share receivers can use the actual basename instead of the supplied label.
/// Keep these copies inside the task directory so task deletion cleans them up.
Future<File> namedAgentFile(File source, String name) async {
  final cleaned = name.replaceAll(RegExp(r'[\x00-\x1f/\\<>:"|?*]'), '').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    throw const FormatException('Artifact name');
  }
  final folder = Directory(p.join(source.parent.path, 'shared'));
  await folder.create(recursive: true);
  final delivery = await folder.createTemp('file-');
  try {
    return await source.copy(p.join(delivery.path, cleaned));
  } catch (_) {
    await delivery.delete(recursive: true);
    rethrow;
  }
}

Future<void> openOrShareAgentFile(
  BuildContext context,
  File file,
  String name,
) async {
  final copy = await namedAgentFile(file, name);
  if (isDesktopApp) {
    await revealFileInManager(copy);
    return;
  }
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  final actualName = p.basename(copy.path);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(
          copy.path,
          name: actualName,
          mimeType:
              AgentArtifactFormat.forName(actualName)?.mimeType ?? 'text/plain',
        ),
      ],
      fileNameOverrides: [actualName],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

class AgentFileActionButton extends StatelessWidget {
  const AgentFileActionButton({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: T(isDesktopApp ? 'i18n.agent_open_folder' : 'i18n.share'),
    child: CupertinoButton(
      padding: const EdgeInsets.all(8),
      onPressed: onPressed,
      child: Icon(
        isDesktopApp ? CupertinoIcons.folder : CupertinoIcons.share,
        size: 20,
        color: IosColors.blue,
      ),
    ),
  );
}

Future<V?> _choice<V>(
  BuildContext context,
  List<DesktopPopupEntry<V>> entries,
) => isDesktopApp
    ? showDesktopPopupMenu(context: context, entries: entries)
    : showCupertinoModalPopup<V>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          actions: [
            for (final entry in entries)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, entry.value),
                child: Text(entry.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(T('i18n.cancel')),
          ),
        ),
      );

Future<void> exportAgentResult(
  BuildContext context,
  AgentTask task, {
  Map<String, dynamic>? artifact,
}) async {
  try {
    final repository = AgentStore();
    final source = artifact == null
        ? (content: task.answer, table: false)
        : await repository.artifactSource(task, artifact);
    if (!context.mounted) return;
    final formats = source.table
        ? [AgentArtifactFormat.csv, AgentArtifactFormat.excel]
        : [
            AgentArtifactFormat.markdown,
            AgentArtifactFormat.pdf,
            AgentArtifactFormat.word,
          ];
    final format = await _choice(context, [
      for (final f in formats)
        DesktopPopupEntry(
          f,
          '${f.label} (.${f.extension})',
          CupertinoIcons.doc,
        ),
    ]);
    if (format == null) return;
    final bytes = await encodeAgentArtifact(format, source.content);
    final parent = (await repository.artifactFile(task, {
      'file': 'report.md',
    })).parent;
    final folder = Directory('${parent.path}/exports');
    await folder.create(recursive: true);
    final hash = sha256.convert(bytes).toString().substring(0, 32);
    final file = File('${folder.path}/$hash.${format.extension}');
    await file.writeAsBytes(bytes, flush: true);
    final original = artifact?['name'] as String? ?? 'AI Link';
    final dot = original.lastIndexOf('.');
    final name =
        '${dot > 0 ? original.substring(0, dot) : original}.${format.extension}';
    if (isDesktopApp) {
      final location = await files.getSaveLocation(suggestedName: name);
      if (location != null && location.path != file.path) {
        await file.copy(location.path);
      }
    } else if (context.mounted) {
      await openOrShareAgentFile(context, file, name);
    }
  } catch (_) {
    if (context.mounted) {
      await agentResultNotice(context, T('i18n.agent_export_failed'));
    }
  }
}

Future<void> saveAgentNote(
  BuildContext context,
  AgentTask task, {
  Map<String, dynamic>? artifact,
}) async {
  try {
    final source = artifact == null
        ? task.answer
        : (await AgentStore().artifactSource(task, artifact)).content;
    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      appPageRoute(
        builder: (_) =>
            _AgentNoteEditor(task: task, artifact: artifact, content: source),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      await agentResultNotice(context, T('i18n.attachment_unavailable'));
    }
  }
}

/// The same explicit actions for the final answer and each file's source preview.
class AgentResultActions extends StatefulWidget {
  const AgentResultActions({super.key, required this.task, this.artifact});
  final AgentTask task;
  final Map<String, dynamic>? artifact;
  @override
  State<AgentResultActions> createState() => _AgentResultActionsState();
}

class _AgentResultActionsState extends State<AgentResultActions> {
  bool _busy = false;
  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 18,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (_busy) const CupertinoActivityIndicator(),
      Builder(
        builder: (anchor) => CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 8),
          minimumSize: Size.zero,
          onPressed: _busy
              ? null
              : () => _perform(
                  () => exportAgentResult(
                    anchor,
                    widget.task,
                    artifact: widget.artifact,
                  ),
                ),
          child: Text(T('i18n.agent_export')),
        ),
      ),
      CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 8),
        minimumSize: Size.zero,
        onPressed: _busy
            ? null
            : () => _perform(
                () => saveAgentNote(
                  context,
                  widget.task,
                  artifact: widget.artifact,
                ),
              ),
        child: Text(T('i18n.agent_save_note')),
      ),
    ],
  );
}

class _AgentNoteEditor extends StatefulWidget {
  const _AgentNoteEditor({
    required this.task,
    required this.content,
    this.artifact,
  });
  final AgentTask task;
  final String content;
  final Map<String, dynamic>? artifact;
  @override
  State<_AgentNoteEditor> createState() => _AgentNoteEditorState();
}

class _AgentNoteEditorState extends State<_AgentNoteEditor> {
  late final _title = TextEditingController(
    text: agentNoteName(
      (widget.artifact?['name'] as String? ?? widget.task.goal).characters
          .take(120)
          .toString(),
      table:
          AgentArtifactFormat.forName(widget.artifact?['file'] as String? ?? '')
              ?.table ??
          false,
    ),
  );
  late final _body = TextEditingController(text: widget.content);
  late int? _projectId = widget.task.projectId;
  String? _projectName;
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _loadProject();
  }

  Future<void> _loadProject() async {
    try {
      final project = await ChatStore.instance.project(_projectId);
      if (mounted) {
        setState(() {
          _projectId = project?.id;
          _projectName = project?.name;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_save_failed'));
    }
  }

  Future<void> _select() async {
    final selection = await Navigator.push<ProjectSelection>(
      context,
      appPageRoute(
        builder: (_) =>
            const ProjectsScreen(moving: true, allowUngrouped: false),
      ),
    );
    if (!mounted || selection == null) return;
    _projectId = selection.id;
    await _loadProject();
  }

  Future<void> _save() async {
    if (_saving || _projectId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await AgentStore().saveProjectNote(
        widget.task,
        _projectId!,
        _title.text,
        _body.text,
        sourceKey: widget.artifact?['file'] as String? ?? 'answer',
      );
      if (!mounted) return;
      await agentResultNotice(
        context,
        T(saved.created ? 'i18n.agent_note_saved' : 'i18n.agent_note_exists'),
      );
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.agent_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.agent_save_note'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () {
          if (!_saving) Navigator.pop(context);
        },
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          IosSection(
            footer: T('i18n.agent_note_detail'),
            children: [
              IosRow(
                title: T('i18n.projects'),
                subtitle: _projectName ?? T('i18n.agent_select_project'),
                onTap: _saving ? null : _select,
              ),
            ],
          ),
          CupertinoTextField(
            controller: _title,
            maxLength: 255,
            placeholder: T('i18n.agent_note_title'),
            enabled: !_saving,
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _body,
            maxLength: 200000,
            minLines: 10,
            maxLines: null,
            enabled: !_saving,
            padding: const EdgeInsets.all(12),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: IosColors.destructive),
              ),
            ),
          const SizedBox(height: 16),
          IosPrimaryButton(
            label: 'i18n.save',
            onPressed: _saving || _projectId == null ? null : _save,
          ),
        ],
      ),
    ),
  );
}
