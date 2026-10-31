import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/chat/assistant_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

Widget _projectField({
  required TextEditingController controller,
  required int maxLength,
  String? placeholder,
  int? maxLines = 1,
  int? minLines,
}) => CupertinoTextField(
  controller: controller,
  maxLength: maxLength,
  placeholder: placeholder,
  maxLines: maxLines,
  minLines: minLines,
  padding: const EdgeInsets.all(10),
  style: TextStyle(color: IosColors.label),
  placeholderStyle: TextStyle(color: IosColors.secondary),
  decoration: BoxDecoration(
    color: IosColors.background,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: IosColors.separator, width: .5),
  ),
);

class ProjectSelection {
  const ProjectSelection(this.id, {this.ungrouped = false});
  final int? id;
  final bool ungrouped;
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    this.moving = false,
    this.allowUngrouped = true,
  });
  final bool moving;
  final bool allowUngrouped;
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ChatProject> _projects = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await ChatStore.instance.projects();
    if (mounted) setState(() => _projects = projects);
  }

  Future<void> _edit(ChatProject? project) async {
    await Navigator.of(
      context,
    ).push(appPageRoute<void>(builder: (_) => ProjectScreen(project: project)));
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.maybePop(context),
      ),
      title: T('i18n.projects'),
      actions: [
        IosNavButton(icon: CupertinoIcons.add, onPressed: () => _edit(null)),
      ],
    ),
    body: ListView(
      children: [
        if (!widget.moving || widget.allowUngrouped)
          IosSection(
            children: [
              if (!widget.moving)
                IosRow(
                  title: T('i18n.all_chats'),
                  leading: Icon(CupertinoIcons.tray_2, color: IosColors.blue),
                  onTap: () =>
                      Navigator.pop(context, const ProjectSelection(null)),
                ),
              if (widget.allowUngrouped)
                IosRow(
                  title: T('i18n.ungrouped_chats'),
                  leading: Icon(
                    CupertinoIcons.chat_bubble_2,
                    color: IosColors.blue,
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    const ProjectSelection(null, ungrouped: true),
                  ),
                ),
            ],
          ),
        IosSection(
          title: T('i18n.projects'),
          footer: T('i18n.projects_detail'),
          children: [
            for (final project in _projects)
              IosRow(
                title: project.name,
                leading: Icon(CupertinoIcons.folder, color: IosColors.blue),
                onTap: () =>
                    Navigator.pop(context, ProjectSelection(project.id)),
                chevron: false,
                trailing: CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => _edit(project),
                  child: Text(T('i18n.manage_project')),
                ),
              ),
            IosRow(
              title: T('i18n.new_project'),
              leading: Icon(CupertinoIcons.add, color: IosColors.blue),
              onTap: () => _edit(null),
            ),
          ],
        ),
      ],
    ),
  );
}

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, this.project});
  final ChatProject? project;
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late final _name = TextEditingController(text: widget.project?.name);
  late final _instructions = TextEditingController(
    text: widget.project?.instructions,
  );
  late final _memory = TextEditingController(text: widget.project?.memory);
  late int? _id = widget.project?.id;
  List<KnowledgeDocument> _documents = [];
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _memory.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_id == null) return;
    final docs = await ChatStore.instance.knowledgeDocuments(_id!);
    if (mounted) setState(() => _documents = docs);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : T('i18n.project_operation_failed'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    _id = await ChatStore.instance.saveProject(
      id: _id,
      name: _name.text,
      instructions: _instructions.text,
      memory: _memory.text,
    );
  }

  Future<void> _import() => _run(() async {
    final selected = await files.openFile();
    if (selected == null) return;
    // Bound the stream before decoding, including cloud-backed or changing files.
    final bytes = <int>[];
    await for (final part in File(selected.path).openRead()) {
      if (bytes.length + part.length > 2 * 1024 * 1024) {
        throw FormatException(T('i18n.knowledge_invalid'));
      }
      bytes.addAll(part);
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw FormatException(T('i18n.knowledge_invalid'));
    }
    await _save();
    await ChatStore.instance.addKnowledge(_id!, selected.name, text);
    await _load();
  });
  Future<void> _note() async {
    final name = TextEditingController();
    final body = TextEditingController();
    final saved = await Navigator.of(context).push<bool>(
      appPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: IosColors.background,
          appBar: iosAppBar(
            leading: IosNavButton(
              icon: CupertinoIcons.back,
              onPressed: () => Navigator.maybePop(context),
            ),
            title: T('i18n.knowledge_note'),
            actions: [
              CupertinoButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(T('i18n.save')),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _projectField(
                  controller: name,
                  maxLength: 255,
                  placeholder: T('i18n.knowledge_name'),
                ),
                const SizedBox(height: 16),
                _projectField(
                  controller: body,
                  maxLines: null,
                  minLines: 12,
                  maxLength: 200000,
                  placeholder: T('i18n.knowledge_content'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      await _run(() async {
        await _save();
        await ChatStore.instance.addKnowledge(_id!, name.text, body.text);
        await _load();
      });
    }
    name.dispose();
    body.dispose();
  }

  Future<void> _document(KnowledgeDocument doc) async {
    final text = await ChatStore.instance.knowledgeText(doc.id);
    if (!mounted) return;
    final remove = await Navigator.of(context).push<bool>(
      appPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: IosColors.background,
          appBar: iosAppBar(
            leading: IosNavButton(
              icon: CupertinoIcons.back,
              onPressed: () => Navigator.maybePop(context),
            ),
            title: doc.name,
            actions: [
              Semantics(
                label: T('i18n.copy_message'),
                button: true,
                child: IosNavButton(
                  icon: CupertinoIcons.doc_on_doc,
                  onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                ),
              ),
              CupertinoButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(T('i18n.delete')),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                doc.name.toLowerCase().endsWith('.md') ||
                    doc.name.toLowerCase().endsWith('.markdown')
                ? AssistantMarkdown(
                    loadImages: false,
                    data: text,
                    onTapLink: (url) async {
                      final uri = Uri.tryParse(url ?? '');
                      if (uri == null ||
                          !{'http', 'https'}.contains(uri.scheme) ||
                          uri.host.isEmpty) {
                        return;
                      }
                      try {
                        if (await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          return;
                        }
                      } catch (_) {}
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(T('i18n.unable_to_open_this_link')),
                          ),
                        );
                      }
                    },
                  )
                : SelectableText(
                    text,
                    style: TextStyle(color: IosColors.label),
                  ),
          ),
        ),
      ),
    );
    if (remove == true &&
        mounted &&
        await _confirm(T('i18n.knowledge_delete_detail'))) {
      await _run(() async {
        await ChatStore.instance.deleteKnowledge(doc.id);
        await _load();
      });
    }
  }

  Future<bool> _confirm(String message) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(T('i18n.delete')),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: Text(T('i18n.cancel')),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(T('i18n.delete')),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.maybePop(context),
      ),
      title: T('i18n.project_space'),
      actions: [
        CupertinoButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await _save();
                  if (mounted) Navigator.of(this.context).pop();
                }),
          child: Text(T('i18n.save')),
        ),
      ],
    ),
    body: AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          if (_busy) const CupertinoActivityIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: IosColors.destructive),
              ),
            ),
          IosSection(
            title: T('i18n.project_name'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _projectField(
                  controller: _name,
                  maxLength: 60,
                  placeholder: T('i18n.project_name'),
                ),
              ),
            ],
          ),
          IosSection(
            title: T('i18n.project_instructions'),
            footer: T('i18n.project_instructions_detail'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _projectField(
                  controller: _instructions,
                  maxLines: null,
                  minLines: 3,
                  maxLength: 8000,
                  placeholder: T('i18n.project_instructions'),
                ),
              ),
            ],
          ),
          IosSection(
            title: T('i18n.project_memory'),
            footer: T('i18n.project_memory_detail'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: _projectField(
                  controller: _memory,
                  maxLines: null,
                  minLines: 3,
                  maxLength: 4000,
                  placeholder: T('i18n.project_memory'),
                ),
              ),
            ],
          ),
          IosSection(
            title: T('i18n.knowledge_base'),
            footer: T('i18n.knowledge_detail'),
            children: [
              for (final doc in _documents)
                IosRow(
                  title: doc.name,
                  subtitle: F('i18n.knowledge_characters', [doc.characters]),
                  leading: Icon(CupertinoIcons.doc_text, color: IosColors.blue),
                  onTap: () => _document(doc),
                ),
              IosRow(
                title: T('i18n.knowledge_import'),
                leading: Icon(CupertinoIcons.folder, color: IosColors.blue),
                onTap: _import,
              ),
              IosRow(
                title: T('i18n.knowledge_note'),
                leading: Icon(
                  CupertinoIcons.square_pencil,
                  color: IosColors.blue,
                ),
                onTap: _note,
              ),
            ],
          ),
          if (_id != null)
            IosSection(
              children: [
                IosRow(
                  title: T('i18n.delete_project'),
                  onTap: () async {
                    if (await _confirm(T('i18n.delete_project_detail'))) {
                      await _run(() async {
                        await ChatStore.instance.deleteProject(_id!);
                        if (mounted) Navigator.of(this.context).pop();
                      });
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
