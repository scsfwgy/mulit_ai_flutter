import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';


import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class PromptSettingsScreen extends StatefulWidget {
  const PromptSettingsScreen({super.key});

  @override
  State<PromptSettingsScreen> createState() => _PromptSettingsScreenState();
}

class _PromptSettingsScreenState extends State<PromptSettingsScreen> {
  String _global = '';
  List<ProviderConfig> _providers = [];
  List<ModelPrompt> _modelPrompts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>([
      ChatStore.instance.globalPrompt(),
      ChatStore.instance.providers(),
      ChatStore.instance.modelPrompts(),
    ]);
    if (!mounted) return;
    setState(() {
      _global = results[0] as String;
      _providers = results[1] as List<ProviderConfig>;
      _modelPrompts = results[2] as List<ModelPrompt>;
    });
  }

  Future<void> _edit({ModelPrompt? modelPrompt, bool global = false}) async {
    await Navigator.push<bool>(
      context,
      appPageRoute(
        builder: (_) => PromptEditor(
          globalText: global ? _global : null,
          providers: global ? null : _providers,
          existing: modelPrompt,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.prompts'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: T('i18n.global'),
            footer: T('i18n.applied_to_every_model_request'),
            children: [
              IosRow(
                title: T('i18n.global_prompt'),
                subtitle: _global.isEmpty ? T('i18n.not_set_short') : _preview(_global),
                leading: Icon(CupertinoIcons.text_quote, color: IosColors.blue),
                onTap: () => _edit(global: true),
              ),
            ],
          ),
          IosSection(
            title: T('i18n.per_model'),
            footer: T('i18n.set_per_service_and_model'),
            children: [
              for (final item in _modelPrompts)
                IosRow(
                  title: item.model,
                  subtitle:
                      '${_providerName(item.providerId)} · ${_preview(item.prompt)}',
                  leading: Icon(
                    CupertinoIcons.square_list,
                    color: IosColors.blue,
                  ),
                  onTap: () => _edit(modelPrompt: item),
                ),
              IosRow(
                title: T('i18n.add_model_prompt'),
                leading: Icon(
                  CupertinoIcons.add_circled,
                  color: IosColors.blue,
                ),
                onTap: _providers.isEmpty ? null : () => _edit(),
              ),
            ],
          ),
          if (_providers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 14, 30, 0),
              child: Text(
                T('i18n.add_a_model_service_hint'),
                style: TextStyle(color: IosColors.secondary, fontSize: 13),
              ),
            ),
        ],
      ),
    ),
  );

  String _providerName(int id) =>
      _providers
          .where((item) => item.id == id)
          .map((item) => item.name)
          .firstOrNull ??
      T('i18n.deleted_service');

  String _preview(String value) {
    final line = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > 36 ? '${line.substring(0, 36)}…' : line;
  }
}

class PromptEditor extends StatefulWidget {
  const PromptEditor({
    super.key,
    this.globalText,
    this.providers,
    this.existing,
  });

  final String? globalText;
  final List<ProviderConfig>? providers;
  final ModelPrompt? existing;

  @override
  State<PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<PromptEditor> {
  late final TextEditingController _model;
  late final TextEditingController _prompt;
  int? _providerId;
  bool _busy = false;

  bool get _global => widget.providers == null;

  @override
  void initState() {
    super.initState();
    _providerId =
        widget.existing?.providerId ?? widget.providers?.firstOrNull?.id;
    _model = TextEditingController(
      text:
          widget.existing?.model ?? widget.providers?.firstOrNull?.model ?? '',
    );
    _prompt = TextEditingController(
      text: widget.globalText ?? widget.existing?.prompt ?? '',
    );
  }

  @override
  void dispose() {
    _model.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _chooseProvider() async {
    final selected = await showAppModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(T('i18n.choose_service')),
        actions: [
          for (final provider in widget.providers!)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, provider.id),
              child: Text(provider.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _providerId = selected;
        _model.text = widget.providers!
            .firstWhere((item) => item.id == selected)
            .model;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final prompt = _prompt.text.trim();
    if (!_global &&
        (_providerId == null || _model.text.trim().isEmpty || prompt.isEmpty)) {
      _showError(T('i18n.choose_a_service_then_enter'));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_global) {
        await ChatStore.instance.saveGlobalPrompt(prompt);
      } else {
        final model = _model.text.trim();
        await ChatStore.instance.saveModelPrompt(_providerId!, model, prompt);
        final previous = widget.existing;
        if (previous != null &&
            (previous.providerId != _providerId || previous.model != model)) {
          await ChatStore.instance.deleteModelPrompt(
            previous.providerId,
            previous.model,
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _showError(error.toString());
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.delete_model_prompt')),
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
    );
    if (confirmed != true) return;
    await ChatStore.instance.deleteModelPrompt(
      existing.providerId,
      existing.model,
    );
    if (mounted) Navigator.pop(context, true);
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.unable_to_save')),
        content: Text(T(message)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(T('i18n.ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedProvider = widget.providers
        ?.where((item) => item.id == _providerId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: _global ? T('i18n.global_prompt') : T('i18n.model_prompts'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.existing != null)
            IosNavButton(icon: CupertinoIcons.delete, onPressed: _delete),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (!_global)
                    IosSection(
                      title: T('i18n.applies'),
                      footer: widget.existing == null
                          ? T('i18n.model_id_manual_hint')
                          : T('i18n.the_saved_service_and_model'),
                      children: [
                        IosRow(
                          title: T('i18n.model_services'),
                          subtitle: selectedProvider?.name ?? T('i18n.please_choose'),
                          onTap: widget.existing == null
                              ? _chooseProvider
                              : null,
                          chevron: widget.existing == null,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: CupertinoTextField(
                            controller: _model,
                            readOnly: widget.existing != null,
                            placeholder: T('i18n.model_id'),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  IosSection(
                    title: T('i18n.system_prompt'),
                    footer: _global
                        ? T('i18n.clear_and_save_to_disable')
                        : T('i18n.applied_only_to_this_service'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: CupertinoTextField(
                          controller: _prompt,
                          placeholder: T('i18n.describe_the_rules_role'),
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
                label: _busy ? T('i18n.saving') : T('i18n.save_prompt'),
                onPressed: _busy ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
