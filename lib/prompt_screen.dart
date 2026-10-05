import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';

import 'data.dart';
import 'ios_style.dart';

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
      title: '提示词',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: '全局',
            footer: '在所有模型的每次请求中生效。',
            children: [
              IosRow(
                title: '全局提示词',
                subtitle: _global.isEmpty ? '尚未设置' : _preview(_global),
                leading: Icon(CupertinoIcons.text_quote, color: IosColors.blue),
                onTap: () => _edit(global: true),
              ),
            ],
          ),
          IosSection(
            title: '单模型',
            footer: '按服务和模型 ID 区分；发送时接在全局提示词之后。留空的模型只使用全局提示词。',
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
                title: '新增模型提示词',
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
                tr('接入模型服务后，即可为指定模型设置提示词。'),
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
      '已删除的服务';

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
        title: Text(tr('选择服务')),
        actions: [
          for (final provider in widget.providers!)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, provider.id),
              child: Text(provider.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
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
      _showError('请选择服务，并填写模型 ID 和提示词');
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
        title: Text(tr('删除模型提示词？')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('取消')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('删除')),
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
        title: Text(tr('无法保存')),
        content: Text(tr(message)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('好')),
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
        title: _global ? '全局提示词' : '模型提示词',
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
                      title: '适用模型',
                      footer: widget.existing == null
                          ? '模型 ID 可以手动填写，例如当前服务的默认模型。'
                          : '已保存的服务和模型 ID 固定；需要更换时请新增一条。',
                      children: [
                        IosRow(
                          title: '模型服务',
                          subtitle: selectedProvider?.name ?? '请选择',
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
                            placeholder: tr('模型 ID'),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  IosSection(
                    title: '系统提示词',
                    footer: _global
                        ? '清空并保存即可关闭全局提示词。'
                        : '仅对上方服务与模型 ID 的请求生效，不会显示在聊天记录中。',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: CupertinoTextField(
                          controller: _prompt,
                          placeholder: tr('写下模型应遵循的规则、角色或输出格式'),
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
                label: _busy ? '正在保存…' : '保存提示词',
                onPressed: _busy ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
