import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/provider/api_key_help.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/provider/provider_qr_scanner.dart';
import 'package:mulit_ai_flutter/voice/voice_catalog.dart';
import 'package:mulit_ai_flutter/voice/voice_selection.dart';
import 'package:mulit_ai_flutter/voice/system_voice.dart';
import 'package:mulit_ai_flutter/voice/voice_client.dart';
import 'package:mulit_ai_flutter/voice/voice_catalog_picker.dart';

class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});
  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen>
    with StorefrontAware {
  List<VoiceProviderConfig> _services = [];
  String? _asrId;
  String? _ttsId;
  String _systemVoiceIdentifier = '';
  List<SystemSpeechVoice> _systemVoices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ChatStore.instance;
    final services = await store.voiceProviders();
    var asr = await selectedVoiceId(store, 'voice_asr_id');
    var tts = await selectedVoiceId(store, 'voice_tts_id');
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
    final systemVoiceIdentifier =
        await store.setting(systemSpeechVoiceSetting) ?? '';
    var systemVoices = <SystemSpeechVoice>[];
    if (supportsSystemVoice && tts == systemVoiceId) {
      try {
        systemVoices = await SystemVoice.availableVoices();
      } on VoiceException {
        // The picker retries if the native service was temporarily unavailable.
      }
    }
    if (mounted) {
      setState(() {
        _services = services;
        _asrId = asr;
        _ttsId = tts;
        _systemVoiceIdentifier = systemVoiceIdentifier;
        _systemVoices = systemVoices;
      });
    }
  }

  String _name(String? id) => id == systemVoiceId && supportsSystemVoice
      ? T('i18n.apple_system_voice')
      : _services.where((item) => item.id == id).firstOrNull?.name ??
            T('i18n.not_set');

  Future<void> _choose(bool asr) async {
    final value = await showAppModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(
          T(asr ? 'i18n.transcription_service' : 'i18n.speech_service'),
        ),
        actions: [
          if (supportsSystemVoice)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, systemVoiceId),
              child: Text(T('i18n.apple_system_voice')),
            ),
          for (final service in _services.where(
            (s) => !StorefrontPolicy.instance.blocks(
              s.baseUrl,
              model: asr ? s.asrModel : s.ttsModel,
            ),
          ))
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, service.id),
              child: Text(service.name),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(T('i18n.none')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
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

  Future<void> _chooseSystemVoice() async {
    try {
      final voices = await SystemVoice.availableVoices();
      if (!mounted) return;
      final prefix = AppPreferences.instance.english ? 'en' : 'zh';
      final choices =
          voices.where((voice) => voice.language.startsWith(prefix)).toList()
            ..sort((a, b) => a.label.compareTo(b.label));
      final value = await showAppModalPopup<String>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: Text(T('i18n.system_speech_voice')),
          message: Text(T('i18n.system_speech_voice_hint')),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(T('i18n.system_voice_default')),
            ),
            for (final voice in choices)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context, voice.identifier),
                child: Text(voice.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(T('i18n.cancel')),
          ),
        ),
      );
      if (value == null) return;
      await ChatStore.instance.saveSetting(systemSpeechVoiceSetting, value);
      await _load();
    } on VoiceException catch (error) {
      if (!mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          content: Text(error.message),
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

  Future<void> _edit([VoiceProviderConfig? service]) async {
    await Navigator.push<void>(
      context,
      appPageRoute(builder: (_) => VoiceServiceEditor(service: service)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.voice_services'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            footer: T(
              supportsSystemVoice
                  ? 'i18n.system_voice_setup_hint'
                  : isDesktopApp
                  ? 'i18n.hold_to_record_slide_left'
                  : 'i18n.hold_to_record_on_phone',
            ),
            children: [
              IosRow(
                title: T('i18n.transcription_service'),
                subtitle: _name(_asrId),
                leading: Icon(CupertinoIcons.mic, color: IosColors.blue),
                onTap: () => _choose(true),
              ),
              IosRow(
                title: T('i18n.speech_service'),
                subtitle: _name(_ttsId),
                leading: Icon(CupertinoIcons.speaker_2, color: IosColors.blue),
                onTap: () => _choose(false),
              ),
              if (supportsSystemVoice && _ttsId == systemVoiceId)
                IosRow(
                  title: T('i18n.system_speech_voice'),
                  subtitle:
                      _systemVoices
                          .where(
                            (voice) =>
                                voice.identifier == _systemVoiceIdentifier,
                          )
                          .firstOrNull
                          ?.label ??
                      T('i18n.system_voice_default'),
                  leading: Icon(CupertinoIcons.person, color: IosColors.blue),
                  onTap: _chooseSystemVoice,
                ),
              IosRow(
                title: T('i18n.read_replies_aloud_automatically'),
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
            title: T('i18n.voice_providers'),
            footer: T('i18n.reuse_a_text_key_only'),
            children: [
              for (final service in _services)
                IosRow(
                  title: service.name,
                  subtitle:
                      (StorefrontPolicy.instance.blocks(
                            service.baseUrl,
                            model: service.asrModel,
                          ) ||
                          StorefrontPolicy.instance.blocks(
                            service.baseUrl,
                            model: service.ttsModel,
                          ))
                      ? T('i18n.openai_storefront_unavailable')
                      : '${service.protocol.name} · ${service.textProviderId == null ? T('i18n.separate_key') : T('i18n.reuse_text_provider')}',
                  leading: Icon(CupertinoIcons.waveform, color: IosColors.blue),
                  onTap: () => _edit(service),
                ),
              IosRow(
                title: T('i18n.add_voice_provider'),
                leading: Icon(
                  CupertinoIcons.add_circled,
                  color: IosColors.blue,
                ),
                onTap: _edit,
              ),
            ],
          ),
          if (supportsSystemVoice)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Text(
                T('i18n.watch_system_dictation_recommendation'),
                style: TextStyle(fontSize: 13, color: IosColors.secondary),
              ),
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

class _VoiceServiceEditorState extends State<VoiceServiceEditor>
    with StorefrontAware {
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
    _name = TextEditingController(text: service?.name ?? T('i18n.xiaomi_mimo'));
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
    VoiceProtocol.openAi =>
      StorefrontPolicy.instance.restricted
          ? 'i18n.compatible_voice_service'
          : 'i18n.openai_compatible_audio',
    VoiceProtocol.mimo => 'i18n.xiaomi_mimo',
    VoiceProtocol.doubao => 'i18n.doubao_speech',
  };

  void _selectProtocol(VoiceProtocol value) {
    setState(() {
      _protocol = value;
      _textProviderId = null;
      switch (value) {
        case VoiceProtocol.openAi:
          final restricted = StorefrontPolicy.instance.restricted;
          _name.text = T(
            restricted
                ? 'i18n.compatible_voice_service'
                : 'i18n.voice_default_name_openai',
          );
          _url.text = restricted ? '' : 'https://api.openai.com/v1';
          _asr.text = restricted ? '' : 'gpt-transcribe';
          _tts.text = restricted ? '' : 'gpt-4o-mini-tts';
          _voice.text = restricted ? '' : 'coral';
        case VoiceProtocol.mimo:
          _name.text = T('i18n.xiaomi_mimo');
          _url.text = 'https://api.xiaomimimo.com/v1';
          _asr.text = 'mimo-v2.5-asr';
          _tts.text = 'mimo-v2.5-tts';
          _voice.text = 'mimo_default';
        case VoiceProtocol.doubao:
          _name.text = T('i18n.doubao_speech');
          _url.text = 'https://openspeech.bytedance.com';
          _asr.text = 'volc.bigasr.auc_turbo';
          _tts.text = 'seed-tts-2.0';
          _voice.text = 'zh_female_vv_uranus_bigtts';
      }
    });
  }

  Future<void> _pickProtocol() async {
    final value = await showAppModalPopup<VoiceProtocol>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(T('i18n.api_protocol')),
        actions: [
          for (final item in VoiceProtocol.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, item),
              child: Text(T(_label(item))),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (value != null) _selectProtocol(value);
  }

  Future<void> _pickKeySource() async {
    final candidates = _textProviders
        .where(
          (item) =>
              !StorefrontPolicy.instance.blocks(
                item.baseUrl,
                presetId: item.presetId,
                model: item.model,
              ) &&
              item.protocol == ApiProtocol.openAi &&
              (_protocol != VoiceProtocol.mimo ||
                  Uri.tryParse(item.baseUrl)?.host == 'api.xiaomimimo.com'),
        )
        .toList();
    final selected = await showAppModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(T('i18n.key_source')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 0),
            child: Text(T('i18n.separate_key')),
          ),
          for (final provider in candidates)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, provider.id),
              child: Text(
                '${T('i18n.reuse_text_provider')} · ${provider.name}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
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
      appPageRoute(
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
        throw FormatException(T('i18n.when_reusing_a_key'));
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
      appPageRoute(
        builder: (_) => VoiceCatalogPicker(
          title: kind == VoiceCatalogKind.voice
              ? T('i18n.choose_voice')
              : T('i18n.choose_model'),
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
          T(label),
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
                        semanticLabel: T('i18n.scan_api_key'),
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
                    T('i18n.choose'),
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
        throw FormatException(T('i18n.enter_a_service_name_model'));
      }
      if (_protocol == VoiceProtocol.mimo &&
          Uri.parse(baseUrl).host != 'api.xiaomimimo.com') {
        throw FormatException(T('i18n.use_the_official_xiaomi_mimo'));
      }
      if (_protocol == VoiceProtocol.doubao &&
          Uri.parse(baseUrl).host != 'openspeech.bytedance.com') {
        throw FormatException(T('i18n.use_the_official_doubao_speech'));
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
        throw FormatException(T('i18n.enter_the_voice_service_api'));
      }
      if (_textProviderId != null &&
          (await ChatStore.instance.apiKey(_textProviderId!))?.isNotEmpty !=
              true) {
        throw FormatException(T('i18n.the_selected_text_provider_has'));
      }
      if (_textProviderId != null &&
          _textProviders
                  .where((item) => item.id == _textProviderId)
                  .firstOrNull
                  ?.baseUrl !=
              baseUrl) {
        throw FormatException(T('i18n.when_reusing_a_key'));
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
            title: Text(T('i18n.unable_to_save')),
            content: Text(
              error is FormatException
                  ? T(error.message)
                  : T('i18n.check_the_configuration_and_try'),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: Text(T('i18n.ok')),
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
        title: Text(T('i18n.delete_voice_provider_confirm')),
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
    if (approved != true) return;
    await ChatStore.instance.deleteVoiceProvider(service.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: widget.service == null
          ? T('i18n.add_voice_provider')
          : T('i18n.edit_voice_provider'),
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
                title: T('i18n.api_protocol'),
                subtitle: T(_label(_protocol)),
                onTap: _pickProtocol,
              ),
              _field('i18n.service_name', _name),
              _field('i18n.api_base_url', _url),
              IosRow(
                title: T('i18n.key_source'),
                subtitle: _textProviderId == null
                    ? T('i18n.separate_key')
                    : _textProviders
                              .where((item) => item.id == _textProviderId)
                              .firstOrNull
                              ?.name ??
                          T('i18n.text_provider_was_deleted'),
                onTap: _protocol == VoiceProtocol.doubao
                    ? null
                    : _pickKeySource,
              ),
              if (_textProviderId == null)
                _field('i18n.api_key_blank_keeps_current', _key, secret: true),
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
            title: T('i18n.voice_models'),
            footer: T('i18n.model_and_voice_ids_must'),
            children: [
              _field(
                'i18n.asr_model_resource_id',
                _asr,
                onPick: () => _pickCatalog(VoiceCatalogKind.asr, _asr),
              ),
              _field(
                'i18n.tts_model_resource_id',
                _tts,
                onPick: () => _pickCatalog(VoiceCatalogKind.tts, _tts),
              ),
              _field(
                'i18n.voice_id',
                _voice,
                onPick: () => _pickCatalog(VoiceCatalogKind.voice, _voice),
              ),
            ],
          ),
          if (widget.service != null)
            IosSection(
              children: [
                IosRow(
                  title: T('i18n.delete_voice_provider'),
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
