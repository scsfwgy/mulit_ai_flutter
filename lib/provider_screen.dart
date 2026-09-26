import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'data.dart';
import 'ios_style.dart';

class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key});

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  List<ProviderConfig> _providers = [];
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final providers = await ChatStore.instance.providers();
    if (mounted) setState(() => _providers = providers);
  }

  Future<void> _edit({ProviderPreset? preset, ProviderConfig? config}) async {
    final changed = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => ProviderEditor(preset: preset, config: config),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _delete(ProviderConfig provider) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除服务配置？'),
        content: Text('删除「${provider.name}」及其密钥。已有话题和记录会保留。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChatStore.instance.deleteProvider(provider.id);
    _changed = true;
    await _load();
  }

  Future<void> _providerActions(ProviderConfig provider) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(provider.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('编辑配置'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('删除服务'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _edit(config: provider);
    if (action == 'delete') await _delete(provider);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: '模型服务',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context, _changed),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: '我的服务',
            footer: '密钥保存在设备安全存储中，聊天记录保存在本机。',
            children: _providers.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        '还没有接入服务。选择下方平台，填写密钥即可开始。',
                        style: TextStyle(
                          color: IosColors.secondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ]
                : [
                    for (final provider in _providers)
                      IosRow(
                        title: provider.name,
                        subtitle:
                            '${provider.model} · ${provider.protocol.label}',
                        leading: _providerBadge(provider.name),
                        trailing: CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(38, 38),
                          onPressed: () => _providerActions(provider),
                          child: const Icon(
                            CupertinoIcons.ellipsis,
                            color: IosColors.secondary,
                            size: 21,
                          ),
                        ),
                        chevron: false,
                        onTap: () => _edit(config: provider),
                      ),
                  ],
          ),
          IosSection(
            title: '快捷接入',
            footer: '已填好常用 API 地址和默认模型。点选平台后输入自己的 API Key。',
            children: [
              for (final preset in providerPresets)
                IosRow(
                  title: preset.name,
                  subtitle: preset.protocol.label,
                  leading: _presetBadge(preset),
                  onTap: () => _edit(preset: preset),
                ),
            ],
          ),
          IosSection(
            title: '其他',
            footer: '支持 OpenAI 兼容 Chat Completions 与 Claude Messages 协议。',
            children: [
              IosRow(
                title: '自定义 API / JSON 导入',
                leading: const Icon(
                  CupertinoIcons.slider_horizontal_3,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: () => _edit(),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    ),
  );
}

Widget _providerBadge(String name) => Container(
  width: 30,
  height: 30,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: IosColors.blue,
    borderRadius: BorderRadius.circular(7),
  ),
  child: Text(
    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
  ),
);

Widget _presetBadge(ProviderPreset preset) => Container(
  width: 30,
  height: 30,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    color: Color(preset.color),
    borderRadius: BorderRadius.circular(7),
  ),
  child: Text(
    preset.initial,
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
  ),
);

class ProviderEditor extends StatefulWidget {
  const ProviderEditor({super.key, this.preset, this.config});
  final ProviderPreset? preset;
  final ProviderConfig? config;

  @override
  State<ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<ProviderEditor> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late final TextEditingController _json;
  late ApiProtocol _protocol;
  bool _jsonMode = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    final preset = widget.preset;
    _name = TextEditingController(text: config?.name ?? preset?.name ?? '');
    _baseUrl = TextEditingController(
      text: config?.baseUrl ?? preset?.baseUrl ?? '',
    );
    _model = TextEditingController(text: config?.model ?? preset?.model ?? '');
    _key = TextEditingController();
    _protocol = config?.protocol ?? preset?.protocol ?? ApiProtocol.openAi;
    _json = TextEditingController();
  }

  @override
  void dispose() {
    for (final controller in [_name, _baseUrl, _model, _key, _json]) {
      controller.dispose();
    }
    super.dispose();
  }

  ({ProviderConfig config, String key}) _formValue() {
    final name = _name.text.trim();
    final model = _model.text.trim();
    if (name.isEmpty || model.isEmpty) {
      throw const FormatException('名称和模型不能为空');
    }
    return (
      config: ProviderConfig(
        id: widget.config?.id ?? 0,
        name: name,
        baseUrl: validateBaseUrl(_baseUrl.text),
        model: model,
        protocol: _protocol,
      ),
      key: _key.text.trim(),
    );
  }

  void _switchMode(bool toJson) {
    try {
      if (toJson) {
        _json.text = const JsonEncoder.withIndent('  ').convert({
          'name': _name.text.trim(),
          'protocol': _protocol.value,
          'baseUrl': _baseUrl.text.trim(),
          'model': _model.text.trim(),
          'apiKey': _key.text.trim(),
        });
      } else {
        final value = ProviderConfig.fromImportJson(
          _json.text,
          id: widget.config?.id ?? 0,
        );
        _name.text = value.config.name;
        _baseUrl.text = value.config.baseUrl;
        _model.text = value.config.model;
        _key.text = value.key;
        _protocol = value.config.protocol;
      }
      setState(() => _jsonMode = toJson);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    try {
      final value = _jsonMode
          ? ProviderConfig.fromImportJson(
              _json.text,
              id: widget.config?.id ?? 0,
            )
          : _formValue();
      if (widget.config == null && value.key.isEmpty) {
        throw const FormatException('请填写 API Key');
      }
      setState(() => _busy = true);
      await ChatStore.instance.saveProvider(
        value.config,
        apiKey: value.key.isEmpty ? null : value.key,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetchModels() async {
    try {
      final value = _jsonMode
          ? ProviderConfig.fromImportJson(
              _json.text,
              id: widget.config?.id ?? 0,
            )
          : _formValue();
      final key = value.key.isNotEmpty
          ? value.key
          : (widget.config == null
                ? null
                : await ChatStore.instance.apiKey(widget.config!.id));
      if (key == null || key.isEmpty) {
        throw const FormatException('请先填写 API Key');
      }
      setState(() => _busy = true);
      final models = await ModelApiClient(value.config, key).fetchModels();
      if (!mounted) return;
      setState(() => _busy = false);
      if (models.isEmpty) throw const ApiException('服务没有返回可用模型');
      final selected = await Navigator.push<String>(
        context,
        CupertinoPageRoute(builder: (_) => _ModelPicker(models: models)),
      );
      if (selected != null && mounted) {
        if (_jsonMode) {
          final decoded = jsonDecode(_json.text) as Map<String, dynamic>;
          decoded['model'] = selected;
          _json.text = const JsonEncoder.withIndent('  ').convert(decoded);
        } else {
          _model.text = selected;
        }
      }
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is FormatException ? error.message : error.toString();
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('配置有误'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseProtocol() async {
    final choice = await showCupertinoModalPopup<ApiProtocol>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('接口协议'),
        actions: [
          for (final kind in ApiProtocol.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, kind),
              child: Text(kind.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _protocol = choice);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: widget.config == null ? '接入模型服务' : '编辑服务配置',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                  child: CupertinoSlidingSegmentedControl<bool>(
                    groupValue: _jsonMode,
                    children: const {
                      false: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('表单'),
                      ),
                      true: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('JSON'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) _switchMode(value);
                    },
                  ),
                ),
                if (_jsonMode)
                  IosSection(
                    title: '完整配置 JSON',
                    footer: '字段：name、protocol、baseUrl、model、apiKey。编辑已有配置时，apiKey 留空表示保留原密钥。',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: CupertinoTextField(
                          controller: _json,
                          minLines: 14,
                          maxLines: 14,
                          autocorrect: false,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.45,
                          ),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: IosColors.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  IosSection(
                    title: '连接设置',
                    footer: '填写 API 根地址，应用会自动拼接 /chat/completions 或 /messages。',
                    children: [
                      _editorField(_name, '服务名称', '例如：我的 OpenAI'),
                      IosRow(
                        title: '接口协议',
                        subtitle: _protocol.label,
                        onTap: _chooseProtocol,
                      ),
                      _editorField(
                        _baseUrl,
                        'API 根地址',
                        'https://api.example.com/v1',
                      ),
                      _editorField(_model, '默认模型', '输入模型 ID'),
                      _editorField(
                        _key,
                        'API Key',
                        widget.config == null ? '粘贴密钥' : '留空则保留原密钥',
                        secret: true,
                      ),
                    ],
                  ),
                IosSection(
                  title: '模型',
                  footer: '获取失败时仍可手动填写模型 ID。密钥不会写入聊天数据库。',
                  children: [
                    IosRow(
                      title: '从服务端获取模型列表',
                      leading: const Icon(
                        CupertinoIcons.arrow_down_circle,
                        color: IosColors.blue,
                        size: 23,
                      ),
                      onTap: _busy ? null : _fetchModels,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: IosPrimaryButton(
              label: _busy ? '请稍候…' : '保存并接入',
              onPressed: _busy ? null : _save,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _editorField(
    TextEditingController controller,
    String label,
    String hint, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: IosColors.secondary, fontSize: 13),
        ),
        const SizedBox(height: 7),
        CupertinoTextField(
          controller: controller,
          placeholder: hint,
          obscureText: secret && _obscure,
          autocorrect: false,
          enableSuggestions: !secret,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: IosColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          suffix: secret
              ? CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 36),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    size: 19,
                    color: IosColors.secondary,
                  ),
                )
              : null,
        ),
      ],
    ),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models});
  final List<String> models;
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.models
        .where((model) => model.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: '选择模型',
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: CupertinoSearchTextField(
                placeholder: '搜索模型 ID',
                onChanged: (value) => setState(() => query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) => Container(
                  decoration: const BoxDecoration(
                    color: IosColors.surface,
                    border: Border(
                      bottom: BorderSide(color: IosColors.separator, width: .5),
                    ),
                  ),
                  child: IosRow(
                    title: shown[index],
                    onTap: () => Navigator.pop(context, shown[index]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
