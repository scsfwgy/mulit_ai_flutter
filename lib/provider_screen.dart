import 'dart:convert';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'data.dart';

const brand = Color(0xFF6558D8);
const ink = Color(0xFF202235);
const canvas = Color(0xFFF6F5F3);

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
      MaterialPageRoute(
        builder: (_) => ProviderEditor(preset: preset, config: config),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _delete(ProviderConfig provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务配置？'),
        content: Text('删除「${provider.name}」及其密钥。已有话题和记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: canvas,
    appBar: AppBar(
      title: const Text('模型服务'),
      backgroundColor: canvas,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context, _changed),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text(
          '已接入',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '密钥保存在设备安全存储中，聊天记录仅保存在本机。',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_providers.isEmpty)
          _surface(
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Text('还没有接入服务。选一个平台，粘贴密钥即可开始。'),
            ),
          )
        else
          ..._providers.map(
            (provider) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _surface(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  leading: _initial(provider.name),
                  title: Text(
                    provider.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${provider.model} · ${provider.protocol.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _edit(config: provider),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => value == 'edit'
                        ? _edit(config: provider)
                        : _delete(provider),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 25),
        const Text(
          '快捷接入',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '预设 API 地址和模型名，只需填写自己的 API Key。',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...providerPresets.map(
          (preset) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _surface(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  backgroundColor: Color(preset.color),
                  child: Text(
                    preset.initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  preset.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(preset.protocol.label),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _edit(preset: preset),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.tune),
          label: const Text('自定义 API / JSON 导入'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '支持 OpenAI 兼容 Chat Completions 与 Claude Messages 协议。'
          '请求会直接从这台设备发送到所配置的服务地址。',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

Widget _surface({required Widget child}) => DecoratedBox(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFEAE8E7)),
  ),
  child: child,
);

Widget _initial(String name) => CircleAvatar(
  backgroundColor: brand.withValues(alpha: .12),
  child: Text(
    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
    style: const TextStyle(color: brand, fontWeight: FontWeight.bold),
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
        final value = _formValue();
        _json.text = const JsonEncoder.withIndent('  ')
            .convert({...value.config.toImportJson(), 'apiKey': value.key});
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
      final selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ModelPicker(models: models),
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
    final message = error is FormatException ? error.message : error.toString();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: canvas,
    appBar: AppBar(
      backgroundColor: canvas,
      title: Text(widget.config == null ? '接入模型服务' : '编辑服务配置'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _surface(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.tune, size: 18),
                          label: Text('表单'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.data_object, size: 18),
                          label: Text('JSON'),
                        ),
                      ],
                      selected: {_jsonMode},
                      onSelectionChanged: (value) => _switchMode(value.first),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_jsonMode) ...[
                  TextField(
                    controller: _json,
                    maxLines: 14,
                    minLines: 14,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      labelText: '完整配置 JSON',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      helperText: '字段：name、protocol、baseUrl、model、apiKey',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '协议值：openai_chat 或 anthropic_messages。编辑已有配置时，'
                    'apiKey 留空表示保留原密钥。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ] else ...[
                  _field(_name, '服务名称', hint: '例如：我的 OpenAI'),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<ApiProtocol>(
                    initialValue: _protocol,
                    decoration: const InputDecoration(
                      labelText: '接口协议',
                      border: OutlineInputBorder(),
                    ),
                    items: ApiProtocol.values
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(kind.label),
                          ),
                        )
                        .toList(),
                    onChanged: (kind) {
                      if (kind != null) setState(() => _protocol = kind);
                    },
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _baseUrl,
                    'API 根地址',
                    hint: 'https://api.example.com/v1',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '填写根地址，应用会自动拼接 /chat/completions 或 /messages。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 18),
                  _field(_model, '默认模型', hint: '输入服务商提供的模型 ID'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _key,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: widget.config == null ? '粘贴密钥' : '留空则保留原密钥',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _busy ? null : _fetchModels,
                  icon: const Icon(Icons.sync),
                  label: const Text('从服务端获取模型列表'),
                ),
                const SizedBox(height: 6),
                const Text(
                  '模型列表获取失败时仍可手动填写模型 ID。密钥不会写入聊天数据库。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: brand,
              ),
              child: Text(_busy ? '请稍候…' : '保存并接入'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) => TextField(
    controller: controller,
    autocorrect: false,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
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
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            const Text(
              '选择模型',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索模型 ID',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(shown[index]),
                  onTap: () => Navigator.pop(context, shown[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
