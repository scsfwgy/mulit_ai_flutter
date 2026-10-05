import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'api_key_help.dart';
import 'data.dart';
import 'ios_style.dart';
import 'provider_qr_scanner.dart';
import 'voice_catalog.dart';
import 'voice_catalog_picker.dart';

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});
  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  List<VoiceProviderConfig> _services = [];
  String? _asrId;
  String? _ttsId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ChatStore.instance;
    final services = await store.voiceProviders();
    var asr = await store.setting('voice_asr_id');
    var tts = await store.setting('voice_tts_id');
    if (services.length == 1) {
      asr ??= services.first.id;
      tts ??= services.first.id;
      if (await store.setting('voice_asr_id') == null) {
        await store.saveSetting('voice_asr_id', asr);
      }
      if (await store.setting('voice_tts_id') == null) {
        await store.saveSetting('voice_tts_id', tts);
      }
    }
    if (mounted) {
      setState(() {
        _services = services;
        _asrId = asr;
        _ttsId = tts;
      });
    }
  }

  String _name(String? id) =>
      _services.where((item) => item.id == id).firstOrNull?.name ?? tr('未设置');

  Future<void> _choose(bool asr) async {
    final value = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(tr(asr ? '语音识别服务' : '语音朗读服务')),
        actions: [
          for (final service in _services)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, service.id),
              child: Text(service.name),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(tr('不使用')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (value == null) return;
    await ChatStore.instance.saveSetting(
      asr ? 'voice_asr_id' : 'voice_tts_id',
      value,
    );
    await _load();
  }

  Future<void> _edit([VoiceProviderConfig? service]) async {
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(builder: (_) => VoiceServiceEditor(service: service)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: tr('语音服务'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            footer: tr(
              '手机按住录音，左滑取消，右滑转文字后确认，直接松手发送。手表左上滑取消，右上滑确认。朗读声音由 AI 生成。',
            ),
            children: [
              IosRow(
                title: '语音识别服务',
                subtitle: _name(_asrId),
                leading: Icon(CupertinoIcons.mic, color: IosColors.blue),
                onTap: () => _choose(true),
              ),
              IosRow(
                title: '语音朗读服务',
                subtitle: _name(_ttsId),
                leading: Icon(CupertinoIcons.speaker_2, color: IosColors.blue),
                onTap: () => _choose(false),
              ),
              IosRow(
                title: '回复完成后自动朗读',
                chevron: false,
                trailing: CupertinoSwitch(
                  value: AppPreferences.instance.autoReadReplies,
                  onChanged: (value) async {
                    await AppPreferences.instance.setAutoReadReplies(value);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
          IosSection(
            title: '语音提供商',
            footer: tr('文字服务密钥仅在接口确实支持语音时可复用。豆包语音须单独填写豆包语音控制台的 API Key。'),
            children: [
              for (final service in _services)
                IosRow(
                  title: service.name,
                  subtitle:
                      '${service.protocol.name} · ${service.textProviderId == null ? tr('独立密钥') : tr('复用文字服务')}',
                  leading: Icon(CupertinoIcons.waveform, color: IosColors.blue),
                  onTap: () => _edit(service),
                ),
              IosRow(
                title: '添加语音提供商',
                leading: Icon(
                  CupertinoIcons.add_circled,
                  color: IosColors.blue,
                ),
                onTap: _edit,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class VoiceServiceEditor extends StatefulWidget {
  const VoiceServiceEditor({super.key, this.service});
  final VoiceProviderConfig? service;
  @override
  State<VoiceServiceEditor> createState() => _VoiceServiceEditorState();
}

class _VoiceServiceEditorState extends State<VoiceServiceEditor> {
  late VoiceProtocol _protocol;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _asr;
  late final TextEditingController _tts;
  late final TextEditingController _voice;
  late final TextEditingController _key;
  int? _textProviderId;
  List<ProviderConfig> _textProviders = [];
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _protocol = service?.protocol ?? VoiceProtocol.mimo;
    _name = TextEditingController(text: service?.name ?? '小米 MiMo');
    _url = TextEditingController(
      text: service?.baseUrl ?? 'https://api.xiaomimimo.com/v1',
    );
    _asr = TextEditingController(text: service?.asrModel ?? 'mimo-v2.5-asr');
    _tts = TextEditingController(text: service?.ttsModel ?? 'mimo-v2.5-tts');
    _voice = TextEditingController(text: service?.voice ?? 'mimo_default');
    _key = TextEditingController();
    _textProviderId = service?.textProviderId;
    ChatStore.instance.providers().then((items) {
      if (mounted) setState(() => _textProviders = items);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _asr, _tts, _voice, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  String _label(VoiceProtocol protocol) => switch (protocol) {
    VoiceProtocol.openAi => 'OpenAI 兼容音频',
    VoiceProtocol.mimo => '小米 MiMo',
    VoiceProtocol.doubao => '豆包语音',
  };

  void _selectProtocol(VoiceProtocol value) {
    setState(() {
      _protocol = value;
      _textProviderId = null;
      switch (value) {
        case VoiceProtocol.openAi:
          _name.text = 'OpenAI 音频';
          _url.text = 'https://api.openai.com/v1';
          _asr.text = 'gpt-transcribe';
          _tts.text = 'gpt-4o-mini-tts';
          _voice.text = 'coral';
        case VoiceProtocol.mimo:
          _name.text = '小米 MiMo';
          _url.text = 'https://api.xiaomimimo.com/v1';
          _asr.text = 'mimo-v2.5-asr';
          _tts.text = 'mimo-v2.5-tts';
          _voice.text = 'mimo_default';
        case VoiceProtocol.doubao:
          _name.text = '豆包语音';
          _url.text = 'https://openspeech.bytedance.com';
          _asr.text = 'volc.bigasr.auc_turbo';
          _tts.text = 'seed-tts-2.0';
          _voice.text = 'zh_female_vv_uranus_bigtts';
      }
    });
  }

  Future<void> _pickProtocol() async {
    final value = await showCupertinoModalPopup<VoiceProtocol>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(tr('接口协议')),
        actions: [
          for (final item in VoiceProtocol.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, item),
              child: Text(tr(_label(item))),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (value != null) _selectProtocol(value);
  }

  Future<void> _pickKeySource() async {
    final candidates = _textProviders
        .where(
          (item) =>
              item.protocol == ApiProtocol.openAi &&
              (_protocol != VoiceProtocol.mimo ||
                  Uri.tryParse(item.baseUrl)?.host == 'api.xiaomimimo.com'),
        )
        .toList();
    final selected = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(tr('密钥来源')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 0),
            child: Text(tr('独立密钥')),
          ),
          for (final provider in candidates)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, provider.id),
              child: Text('${tr('复用文字服务')} · ${provider.name}'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      _textProviderId = selected == 0 ? null : selected;
      final provider = candidates
          .where((item) => item.id == selected)
          .firstOrNull;
      if (provider != null) _url.text = provider.baseUrl;
    });
  }

  Future<void> _scanKey() async {
    final value = await Navigator.push<String>(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            const ProviderQrScanner(mode: ProviderQrScanMode.apiKey),
      ),
    );
    if (value != null && mounted) _key.text = value;
  }

  Future<void> _pickCatalog(
    VoiceCatalogKind kind,
    TextEditingController controller,
  ) async {
    Future<List<VoiceCatalogOption>> refresh() async {
      final baseUrl = validateBaseUrl(_url.text);
      final previous = widget.service;
      final textProvider = _textProviders
          .where((item) => item.id == _textProviderId)
          .firstOrNull;
      if (_textProviderId != null &&
          (textProvider == null || textProvider.baseUrl != baseUrl)) {
        throw const FormatException('复用密钥时，API 根地址须与文字服务一致');
      }
      final key = _textProviderId == null
          ? (_key.text.trim().isNotEmpty
                ? _key.text.trim()
                : previous == null ||
                      previous.textProviderId != null ||
                      previous.baseUrl != baseUrl ||
                      previous.protocol != _protocol
                ? null
                : await ChatStore.instance.voiceApiKey(previous))
          : await ChatStore.instance.apiKey(_textProviderId!);
      final client = VoiceCatalogClient();
      try {
        return await client.fetchModels(
          baseUrl: baseUrl,
          apiKey: key ?? '',
          protocol: _protocol,
          kind: kind,
        );
      } finally {
        client.close();
      }
    }

    final result = await Navigator.push<String>(
      context,
      CupertinoPageRoute(
        builder: (_) => VoiceCatalogPicker(
          title: kind == VoiceCatalogKind.voice ? '选择音色' : '选择模型',
          initialValue: controller.text,
          examples: voiceCatalogExamples(
            _protocol,
            kind,
            ttsModel: _tts.text.trim(),
          ),
          onRefresh:
              _protocol == VoiceProtocol.doubao ||
                  kind == VoiceCatalogKind.voice
              ? null
              : refresh,
        ),
      ),
    );
    if (result != null && mounted) controller.text = result;
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool secret = false,
    VoidCallback? onPick,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(label),
          style: TextStyle(color: IosColors.secondary, fontSize: 13),
        ),
        const SizedBox(height: 5),
        CupertinoTextField(
          controller: controller,
          obscureText: secret && _obscure,
          enableSuggestions: !secret,
          suffix: secret
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      minimumSize: const Size(36, 36),
                      onPressed: _scanKey,
                      child: Icon(
                        CupertinoIcons.qrcode_viewfinder,
                        size: 20,
                        color: IosColors.blue,
                        semanticLabel: tr('扫码填写 API Key'),
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
              : onPick == null
              ? null
              : CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onPressed: onPick,
                  child: Text(
                    tr('选择'),
                    style: TextStyle(color: IosColors.blue),
                  ),
                ),
          autocorrect: false,
          style: TextStyle(color: IosColors.label),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: IosColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final baseUrl = validateBaseUrl(_url.text);
      if (_name.text.trim().isEmpty ||
          _asr.text.trim().isEmpty ||
          _tts.text.trim().isEmpty ||
          _voice.text.trim().isEmpty) {
        throw const FormatException('请填写服务名称、模型 ID 与音色');
      }
      if (_protocol == VoiceProtocol.mimo &&
          Uri.parse(baseUrl).host != 'api.xiaomimimo.com') {
        throw const FormatException('小米 MiMo 请使用官方接口地址');
      }
      if (_protocol == VoiceProtocol.doubao &&
          Uri.parse(baseUrl).host != 'openspeech.bytedance.com') {
        throw const FormatException('豆包语音请使用官方接口地址');
      }
      final id =
          widget.service?.id ??
          DateTime.now().microsecondsSinceEpoch.toString();
      final service = VoiceProviderConfig(
        id: id,
        name: _name.text.trim(),
        protocol: _protocol,
        baseUrl: baseUrl,
        asrModel: _asr.text.trim(),
        ttsModel: _tts.text.trim(),
        voice: _voice.text.trim(),
        textProviderId: _textProviderId,
      );
      final previous = widget.service;
      final changedEndpoint =
          previous != null &&
          (previous.protocol != _protocol || previous.baseUrl != baseUrl);
      if (_textProviderId == null &&
          _key.text.trim().isEmpty &&
          (previous == null ||
              previous.textProviderId != null ||
              changedEndpoint)) {
        throw const FormatException('请填写语音服务 API Key');
      }
      if (_textProviderId != null &&
          (await ChatStore.instance.apiKey(_textProviderId!))?.isNotEmpty !=
              true) {
        throw const FormatException('选中的文字服务缺少 API Key');
      }
      if (_textProviderId != null &&
          _textProviders
                  .where((item) => item.id == _textProviderId)
                  .firstOrNull
                  ?.baseUrl !=
              baseUrl) {
        throw const FormatException('复用密钥时，API 根地址须与文字服务一致');
      }
      await ChatStore.instance.saveVoiceProvider(
        service,
        apiKey: _textProviderId == null ? _key.text : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: Text(tr('无法保存')),
            content: Text(
              error is FormatException ? tr(error.message) : tr('请检查配置后重试'),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('好')),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final service = widget.service;
    if (service == null) return;
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('删除语音提供商？')),
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
    if (approved != true) return;
    await ChatStore.instance.deleteVoiceProvider(service.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: widget.service == null ? '添加语音提供商' : '编辑语音提供商',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IosNavButton(icon: CupertinoIcons.check_mark, onPressed: _save),
      ],
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            children: [
              IosRow(
                title: '接口协议',
                subtitle: tr(_label(_protocol)),
                onTap: _pickProtocol,
              ),
              _field('服务名称', _name),
              _field('API 根地址', _url),
              IosRow(
                title: '密钥来源',
                subtitle: _textProviderId == null
                    ? tr('独立密钥')
                    : _textProviders
                              .where((item) => item.id == _textProviderId)
                              .firstOrNull
                              ?.name ??
                          tr('文字服务已删除'),
                onTap: _protocol == VoiceProtocol.doubao
                    ? null
                    : _pickKeySource,
              ),
              if (_textProviderId == null)
                _field('API Key（留空保留原密钥）', _key, secret: true),
            ],
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _url,
            builder: (context, value, _) => ApiKeyHelpSection(
              category: 'voice',
              officialUrl: voiceApiKeyUrlForEndpoint(_protocol, value.text),
              enabled: !_saving,
            ),
          ),
          IosSection(
            title: '语音模型',
            footer: tr('模型与音色 ID 需要在对应服务开通。豆包语音的模型栏填写资源 ID。'),
            children: [
              _field(
                '识别模型 ID / 资源 ID',
                _asr,
                onPick: () => _pickCatalog(VoiceCatalogKind.asr, _asr),
              ),
              _field(
                '合成模型 ID / 资源 ID',
                _tts,
                onPick: () => _pickCatalog(VoiceCatalogKind.tts, _tts),
              ),
              _field(
                '音色 ID',
                _voice,
                onPick: () => _pickCatalog(VoiceCatalogKind.voice, _voice),
              ),
            ],
          ),
          if (widget.service != null)
            IosSection(
              children: [
                IosRow(
                  title: '删除语音提供商',
                  leading: Icon(
                    CupertinoIcons.delete,
                    color: IosColors.destructive,
                  ),
                  onTap: _delete,
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
