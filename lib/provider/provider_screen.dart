import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';

import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/provider/api_key_help.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/chat/model_picker.dart';
import 'package:mulit_ai_flutter/settings/privacy_screen.dart';
import 'package:mulit_ai_flutter/provider/provider_qr_scanner.dart';
import 'package:mulit_ai_flutter/settings/prompt_screen.dart';
import 'package:mulit_ai_flutter/provider/provider_badge.dart';

class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key, this.canClearData});

  final bool Function()? canClearData;

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> with StorefrontAware {
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
      appPageRoute(
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
      appPageRoute(builder: (_) => const ProviderQrScanner()),
    );
    if (imported == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _openPrivacy() async {
    final cleared = await Navigator.push<bool>(
      context,
      appPageRoute(
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
        title: Text(T('i18n.delete_service_confirm')),
        content: Text(F('i18n.provider_delete_body', [provider.name])),
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
    await ChatStore.instance.deleteProvider(provider.id);
    _changed = true;
    await _load();
  }

  Future<void> _providerActions(ProviderConfig provider) async {
    final action = await showAppModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(provider.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: Text(T('i18n.edit_configuration')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(T('i18n.delete_service')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
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
      title: T('i18n.model_services'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context, _changed),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: T('i18n.my_services'),
            footer: T(
              isDesktopApp
                  ? 'i18n.keys_stay_in_secure_local'
                  : 'i18n.keys_stay_in_secure_phone',
            ),
            children: _providers.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        T('i18n.no_services_yet_choose'),
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
                            StorefrontPolicy.instance.blocks(
                              provider.baseUrl,
                              presetId: provider.presetId,
                              model: provider.model,
                            )
                            ? T('i18n.openai_storefront_unavailable')
                            : '${provider.model} · ${T(provider.protocol.label)}',
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
            title: T('i18n.chat_settings'),
            children: [
              IosRow(
                title: T('i18n.prompts'),
                subtitle: T('i18n.global_and_model_prompts'),
                leading: Icon(
                  CupertinoIcons.text_quote,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(builder: (_) => const PromptSettingsScreen()),
                ),
              ),
            ],
          ),
          IosSection(
            title: T('i18n.privacy_data'),
            children: [
              IosRow(
                title: T('i18n.data_privacy'),
                subtitle: T('i18n.review_storage_and_clear_local'),
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
            title: T('i18n.china_providers'),
            footer: T('i18n.api_urls_and_example_models'),
            children: [
              for (final preset in availableProviderPresets.where(
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
            title: T('i18n.international_providers'),
            children: [
              for (final preset in availableProviderPresets.where(
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
            title: T('i18n.aggregators_inference'),
            children: [
              for (final preset in availableProviderPresets.where(
                (p) => {'openrouter', 'together', 'fireworks'}.contains(p.id),
              ))
                _presetRow(preset),
            ],
          ),
          IosSection(
            title: T('i18n.other'),
            footer: T(
              StorefrontPolicy.instance.restricted
                  ? 'i18n.supports_compatible_chat_protocols'
                  : 'i18n.supports_openai_compatible_chat_completions',
            ),
            children: [
              IosRow(
                title: T('i18n.scan_to_import'),
                subtitle: T('i18n.scan_a_full_json_configuration'),
                leading: Icon(
                  CupertinoIcons.qrcode_viewfinder,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: _scanImport,
              ),
              IosRow(
                title: T('i18n.custom_api_json_import'),
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
    title: T(preset.name),
    subtitle: T(preset.protocol.label),
    leading: ProviderBadge(name: T(preset.name), presetId: preset.id, size: 30),
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

class _ProviderEditorState extends State<ProviderEditor> with StorefrontAware {
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
    _name = TextEditingController(
      text: config?.name ?? (preset == null ? '' : T(preset.name)),
    );
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
      throw FormatException(T('i18n.service_name_and_model_cannot'));
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
        throw FormatException(T('i18n.enter_an_api_key'));
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
      appPageRoute(
        builder: (_) =>
            const ProviderQrScanner(mode: ProviderQrScanMode.apiKey),
      ),
    );
    if (key == null || !mounted) return;
    if (_jsonMode) {
      try {
        final decoded = jsonDecode(_json.text);
        if (decoded is! Map<String, dynamic>) {
          throw FormatException(T('i18n.enter_valid_configuration_json'));
        }
        decoded['apiKey'] = key;
        _json.text = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        _showError(
          FormatException(T('i18n.fix_the_configuration_json_before')),
        );
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
        throw FormatException(T('i18n.enter_an_api_key_first'));
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
        if (models.isEmpty) {
          throw ApiException(T('i18n.the_service_returned_no_usable'));
        }
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
        appPageRoute(
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
        title: Text(T('i18n.invalid_configuration')),
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

  Future<void> _chooseProtocol() async {
    final choice = await showAppModalPopup<ApiProtocol>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(T('i18n.api_protocol')),
        actions: [
          for (final kind in ApiProtocol.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, kind),
              child: Text(T(kind.label)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _protocol = choice);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: widget.config == null
          ? T('i18n.add_a_model_service')
          : T('i18n.edit_service'),
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
                        child: Text(T('i18n.form')),
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
                    title: T('i18n.full_json_configuration'),
                    footer: T('i18n.fields_name_protocol_baseurl_model'),
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
                        title: T('i18n.scan_api_key'),
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
                    title: T('i18n.connection'),
                    footer: T('i18n.enter_the_api_base_url'),
                    children: [
                      _editorField(
                        _name,
                        'i18n.service_name',
                        StorefrontPolicy.instance.restricted
                            ? 'i18n.for_example_my_model_service'
                            : 'i18n.for_example_my_openai',
                      ),
                      IosRow(
                        title: T('i18n.api_protocol'),
                        subtitle: T(_protocol.label),
                        onTap: _chooseProtocol,
                      ),
                      _editorField(
                        _baseUrl,
                        'i18n.api_base_url',
                        'https://api.example.com/v1',
                      ),
                      _editorField(
                        _model,
                        'i18n.default_model',
                        'i18n.enter_model_id',
                      ),
                      _editorField(
                        _key,
                        'API Key',
                        widget.config == null
                            ? 'i18n.paste_key'
                            : 'i18n.leave_blank_to_keep_current',
                        secret: true,
                      ),
                    ],
                  ),
                AnimatedBuilder(
                  animation: Listenable.merge([_baseUrl, _json]),
                  builder: (context, _) {
                    var endpoint = _baseUrl.text;
                    if (_jsonMode) {
                      try {
                        final value = jsonDecode(_json.text);
                        endpoint = value is Map && value['baseUrl'] is String
                            ? value['baseUrl'] as String
                            : '';
                      } catch (_) {
                        endpoint = '';
                      }
                    }
                    return ApiKeyHelpSection(
                      category: 'text',
                      officialUrl: textApiKeyUrlForEndpoint(endpoint),
                      enabled: !_busy,
                    );
                  },
                ),
                IosSection(
                  title: T('i18n.models_short'),
                  footer: T('i18n.shows_the_local_cache_first'),
                  children: [
                    IosRow(
                      title: T('i18n.view_model_list'),
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
              label: _busy ? T('i18n.please_wait') : T('i18n.save_and_connect'),
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
          T(label),
          style: TextStyle(color: IosColors.secondary, fontSize: 13),
        ),
        const SizedBox(height: 7),
        CupertinoTextField(
          controller: controller,
          placeholder: T(hint),
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
