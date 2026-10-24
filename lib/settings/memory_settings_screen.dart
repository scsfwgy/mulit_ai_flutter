import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class MemorySettingsScreen extends StatefulWidget {
  const MemorySettingsScreen({super.key});

  @override
  State<MemorySettingsScreen> createState() => _MemorySettingsScreenState();
}

class _MemorySettingsScreenState extends State<MemorySettingsScreen> {
  bool _loaded = false;
  bool _memoryEnabled = false;
  bool _defaultForChats = false;
  String _memory = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ChatStore.instance;
    final values = await Future.wait<Object>([
      store.memoryEnabled(),
      store.memoryInGlobalPrompt(),
      store.memoryProfile(),
    ]);
    if (!mounted) return;
    setState(() {
      _memoryEnabled = values[0] as bool;
      _defaultForChats = values[1] as bool;
      _memory = values[2] as String;
      _loaded = true;
    });
  }

  Future<void> _setMemoryEnabled(bool enabled) async {
    await ChatStore.instance.setMemoryEnabled(enabled);
    if (mounted) setState(() => _memoryEnabled = enabled);
  }

  Future<void> _editMemory() async {
    final profile = await ChatStore.instance.memoryProfile();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      appPageRoute(builder: (_) => MemoryEditor(initial: profile)),
    );
    await _load();
  }

  Future<void> _clearMemory() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.memory_clear')),
        content: Text(T('i18n.memory_clear_detail')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(T('i18n.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(T('i18n.clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ChatStore.instance.saveMemoryProfile('');
    await _load();
  }

  Future<void> _setDefaultForChats(bool enabled) async {
    await ChatStore.instance.setMemoryInGlobalPrompt(enabled);
    if (mounted) setState(() => _defaultForChats = enabled);
  }

  String _preview(String value) {
    final line = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > 36 ? '${line.substring(0, 36)}…' : line;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.memory'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CupertinoActivityIndicator(),
            ),
          if (_loaded)
            IosSection(
              title: T('i18n.memory'),
              footer: T('i18n.memory_detail'),
              children: [
                IosRow(
                  title: T('i18n.memory'),
                  leading: Icon(
                    CupertinoIcons.person_crop_circle,
                    color: IosColors.blue,
                  ),
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: _memoryEnabled,
                    activeTrackColor: IosColors.blue,
                    onChanged: _setMemoryEnabled,
                  ),
                ),
                IosRow(
                  title: T('i18n.memory_edit'),
                  subtitle: _memory.isEmpty
                      ? T('i18n.not_set_short')
                      : _preview(_memory),
                  leading: Icon(CupertinoIcons.pencil, color: IosColors.blue),
                  onTap: _editMemory,
                ),
                if (_memory.isNotEmpty)
                  IosRow(
                    title: T('i18n.memory_clear'),
                    leading: Icon(
                      CupertinoIcons.delete,
                      color: IosColors.destructive,
                    ),
                    chevron: false,
                    onTap: _clearMemory,
                  ),
              ],
            ),
          if (_loaded)
            IosSection(
              footer: T('i18n.memory_default_for_chats_footer'),
              children: [
                IosRow(
                  title: T('i18n.memory_default_for_chats'),
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: _defaultForChats,
                    activeTrackColor: IosColors.blue,
                    onChanged: _memoryEnabled ? _setDefaultForChats : null,
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class MemoryEditor extends StatefulWidget {
  const MemoryEditor({super.key, required this.initial});

  final String initial;

  @override
  State<MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<MemoryEditor> {
  late final TextEditingController _profile = TextEditingController(
    text: widget.initial,
  );
  bool _busy = false;

  @override
  void dispose() {
    _profile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ChatStore.instance.saveMemoryProfile(_profile.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(T('i18n.unable_to_save')),
            content: Text(T(error.toString())),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: Text(T('i18n.ok')),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.memory'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                IosSection(
                  footer: T('i18n.memory_edit_footer'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: CupertinoTextField(
                        controller: _profile,
                        placeholder: T('i18n.memory_placeholder'),
                        minLines: 11,
                        maxLines: 11,
                        textAlignVertical: TextAlignVertical.top,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: IosColors.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: IosPrimaryButton(
              label: _busy ? T('i18n.saving') : T('i18n.save'),
              onPressed: _busy ? null : _save,
            ),
          ),
        ],
      ),
    ),
  );
}
