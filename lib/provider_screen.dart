import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';

import 'api_client.dart';
import 'data.dart';
import 'ios_style.dart';
import 'model_picker.dart';
import 'privacy_screen.dart';
import 'provider_qr_scanner.dart';
import 'prompt_screen.dart';
import 'provider_badge.dart';

class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key, this.canClearData});

  final bool Function()? canClearData;

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

  Future<void> _scanImport() async {
    final imported = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(builder: (_) => const ProviderQrScanner()),
    );
    if (imported == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _openPrivacy() async {
    final cleared = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => PrivacyScreen(canClearData: widget.canClearData),
      ),
    );
    if (cleared == true) {
      _changed = true;
      await AppPreferences.instance.load();
      await _load();
    }
  }

  Future<void> _delete(ProviderConfig provider) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('删除服务配置？')),
        content: Text(
          AppPreferences.instance.english
              ? 'Delete ${provider.name} and its key? Existing chats are kept.'
              : '删除「${provider.name}」及其密钥。已有话题和记录会保留。',
        ),
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
            child: Text(tr('编辑配置')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(tr('删除服务')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
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
            footer: tr(
              '密钥保存在手机安全存储中；选作手表服务时会经配对通道同步到手表，Wear OS 加密保存，Apple Watch 保存在钥匙串。我们不设中转服务器，请求会直达你配置的 API 服务商。',
            ),
            children: _providers.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        tr('还没有接入服务。选择下方平台，填写密钥即可开始。'),
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
                            '${provider.model} · ${tr(provider.protocol.label)}',
                        leading: ProviderBadge(
                          name: provider.name,
                          presetId: presetForProvider(provider)?.id,
                          size: 30,
                        ),
                        trailing: CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(38, 38),
                          onPressed: () => _providerActions(provider),
                          child: Icon(
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
            title: '对话设置',
            children: [
              IosRow(
                title: '提示词',
                subtitle: '全局和单模型提示词',
                leading: Icon(
                  CupertinoIcons.text_quote,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const PromptSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          IosSection(
            title: '隐私与数据',
            children: [
              IosRow(
                title: '数据与隐私',
                subtitle: '查看存储方式与清空本地数据',
                leading: Icon(
                  CupertinoIcons.lock_shield,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: _openPrivacy,
              ),
            ],
          ),
          IosSection(
            title: '国内服务',
            footer: '已填入 API 地址和示例模型；账号可用模型以服务端为准。',
            children: [
              for (final preset in providerPresets.where(
                (p) => {
                  'deepseek',
                  'glm',
                  'qwen',
                  'doubao',
                  'baidu',
                  'hunyuan',
                  'moonshot',
                  'minimax',
                  'siliconflow',
                }.contains(p.id),
              ))
                _presetRow(preset),
            ],
          ),
          IosSection(
            title: '国际服务',
            children: [
              for (final preset in providerPresets.where(
                (p) => {
                  'openai',
                  'claude',
                  'gemini',
                  'grok',
                  'groq',
                  'mistral',
                  'perplexity',
                }.contains(p.id),
              ))
                _presetRow(preset),
            ],
          ),
          IosSection(
            title: '聚合与推理平台',
            children: [
              for (final preset in providerPresets.where(
                (p) => {'openrouter', 'together', 'fireworks'}.contains(p.id),
              ))
                _presetRow(preset),
            ],
          ),
          IosSection(
            title: '其他',
            footer: '支持 OpenAI 兼容 Chat Completions 与 Claude Messages 协议。',
            children: [
              IosRow(
                title: '扫码导入配置',
                subtitle: '扫描完整配置 JSON 二维码',
                leading: Icon(
                  CupertinoIcons.qrcode_viewfinder,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: _scanImport,
              ),
              IosRow(
                title: '自定义 API / JSON 导入',
                leading: Icon(
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

  Widget _presetRow(ProviderPreset preset) => IosRow(
    title: preset.name,
    subtitle: preset.protocol.label,
    leading: ProviderBadge(name: preset.name, presetId: preset.id, size: 30),
    onTap: () => _edit(preset: preset),
  );
}

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
  String? _presetId;
  bool _jsonMode = false;
  bool _busy = false;
  bool _obscure = true;
  ({
    List<String> models,
    String baseUrl,
    ApiProtocol protocol,
    String inputKey,
  })?
  _pendingModelCache;

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
    _presetId =
        config?.presetId ??
        (config == null ? preset?.id : presetForProvider(config)?.id);
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
        presetId: _presetId,
      ),
      key: _key.text.trim(),
    );
  }

  ({ProviderConfig config, String key}) _jsonValue() {
    final value = ProviderConfig.fromImportJson(
      _json.text,
      id: widget.config?.id ?? 0,
    );
    return (
      config: value.config.copyWith(
        presetId: value.config.presetId ?? _presetId,
      ),
      key: value.key,
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
          if (_presetId != null) 'presetId': _presetId,
        });
      } else {
        final value = _jsonValue();
        _name.text = value.config.name;
        _baseUrl.text = value.config.baseUrl;
        _model.text = value.config.model;
        _key.text = value.key;
        _protocol = value.config.protocol;
        _presetId = value.config.presetId;
      }
      setState(() => _jsonMode = toJson);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    try {
      final value = _jsonMode ? _jsonValue() : _formValue();
      if (widget.config == null && value.key.isEmpty) {
        throw const FormatException('请填写 API Key');
      }
      setState(() => _busy = true);
      final id = await ChatStore.instance.saveProvider(
        value.config,
        apiKey: value.key.isEmpty ? null : value.key,
      );
      final pending = _pendingModelCache;
      if (pending != null &&
          pending.baseUrl == value.config.baseUrl &&
          pending.protocol == value.config.protocol &&
          pending.inputKey == value.key) {
        try {
          await ChatStore.instance.saveModelCache(
            value.config.copyWith(id: id),
            pending.models,
          );
        } catch (_) {
          // The service is saved even if its optional model cache cannot be.
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanApiKey() async {
    final key = await Navigator.push<String>(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            const ProviderQrScanner(mode: ProviderQrScanMode.apiKey),
      ),
    );
    if (key == null || !mounted) return;
    if (_jsonMode) {
      try {
        final decoded = jsonDecode(_json.text);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('请先填写有效的配置 JSON');
        }
        decoded['apiKey'] = key;
        _json.text = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        _showError(const FormatException('请先修正配置 JSON，再扫码填写密钥'));
      }
    } else {
      _key.text = key;
    }
  }

  Future<void> _fetchModels() async {
    try {
      final value = _jsonMode ? _jsonValue() : _formValue();
      final key = value.key.isNotEmpty
          ? value.key
          : (widget.config == null
                ? null
                : await ChatStore.instance.apiKey(widget.config!.id));
      if (key == null || key.isEmpty) {
        throw const FormatException('请先填写 API Key');
      }
      setState(() => _busy = true);
      final savedConfig = widget.config;
      final canUseCache =
          savedConfig != null &&
          value.key.isEmpty &&
          value.config.baseUrl == savedConfig.baseUrl &&
          value.config.protocol == savedConfig.protocol;
      final cached = canUseCache
          ? await ChatStore.instance.cachedModels(value.config)
          : null;
      Future<List<String>> fetchFresh() async {
        final models = await ModelApiClient(value.config, key).fetchModels();
        if (models.isEmpty) throw const ApiException('服务没有返回可用模型');
        _pendingModelCache = (
          models: models,
          baseUrl: value.config.baseUrl,
          protocol: value.config.protocol,
          inputKey: value.key,
        );
        if (canUseCache) {
          try {
            await ChatStore.instance.saveModelCache(value.config, models);
          } catch (_) {
            // The fresh list remains usable when the cache write fails.
          }
        }
        return models;
      }

      final models = cached?.models ?? await fetchFresh();
      if (!mounted) return;
      setState(() => _busy = false);
      final selected = await Navigator.push<String>(
        context,
        CupertinoPageRoute(
          builder: (_) => ModelPicker(
            models: models,
            fetchedAt: cached?.fetchedAt ?? DateTime.now(),
            onRefresh: fetchFresh,
          ),
        ),
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
        title: Text(tr('配置有误')),
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

  Future<void> _chooseProtocol() async {
    final choice = await showCupertinoModalPopup<ApiProtocol>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(tr('接口协议')),
        actions: [
          for (final kind in ApiProtocol.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, kind),
              child: Text(tr(kind.label)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
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
                    children: {
                      false: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(tr('表单')),
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
                    footer: '字段：name、protocol、baseUrl、model、apiKey。编辑时 apiKey 留空表示保留原密钥；JSON 编辑框会明文显示新填入的密钥。',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: CupertinoTextField(
                          controller: _json,
                          minLines: 14,
                          maxLines: 14,
                          autocorrect: false,
                          style: TextStyle(
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
                      IosRow(
                        title: '扫码填写 API Key',
                        leading: Icon(
                          CupertinoIcons.qrcode_viewfinder,
                          color: IosColors.blue,
                          size: 22,
                        ),
                        onTap: _scanApiKey,
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
                        subtitle: tr(_protocol.label),
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
                  footer: '优先显示本地缓存，可在列表中刷新。获取失败时仍可手动填写模型 ID。',
                  children: [
                    IosRow(
                      title: '查看模型列表',
                      leading: Icon(
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
          tr(label),
          style: TextStyle(color: IosColors.secondary, fontSize: 13),
        ),
        const SizedBox(height: 7),
        CupertinoTextField(
          controller: controller,
          placeholder: tr(hint),
          obscureText: secret && _obscure,
          autocorrect: false,
          enableSuggestions: !secret,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: IosColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          suffix: secret
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      minimumSize: const Size(36, 36),
                      onPressed: _scanApiKey,
                      child: Icon(
                        CupertinoIcons.qrcode_viewfinder,
                        size: 20,
                        color: IosColors.blue,
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(36, 36),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                        _obscure
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        size: 19,
                        color: IosColors.secondary,
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ],
    ),
  );
}
