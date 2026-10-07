import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/chat/chat_model_selector.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/voice/voice_settings_screen.dart';

class WatchSettingsScreen extends StatefulWidget {
  const WatchSettingsScreen({super.key});

  @override
  State<WatchSettingsScreen> createState() => _WatchSettingsScreenState();
}

class _WatchSettingsScreenState extends State<WatchSettingsScreen>
    with WidgetsBindingObserver {
  static const _companion = MethodChannel('between_models/companion_install');
  List<ProviderConfig> _providers = [];
  int? _providerId;
  String? _model;
  bool _speak = false;
  int _connectedWatches = 0;
  List<(String, String)> _missingWatches = [];
  bool _checkingWatches = true;
  bool _isAppleWatch = false;
  bool _watchAppInstalled = false;
  bool _watchReachable = false;
  bool _openingStore = false;
  String? _watchCheckError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkWatches();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkWatches();
  }

  Future<void> _checkWatches() async {
    if (mounted) setState(() => _checkingWatches = true);
    try {
      final status = await _companion.invokeMapMethod<String, dynamic>(
        'watchStatus',
      );
      if (!mounted) return;
      final missing = (status?['missing'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                (item['id']?.toString() ?? '', item['name']?.toString() ?? ''),
          )
          .where((item) => item.$1.isNotEmpty)
          .toList();
      setState(() {
        _isAppleWatch = status?['platform'] == 'apple';
        _watchAppInstalled = status?['installed'] == true;
        _watchReachable = status?['reachable'] == true;
        _connectedWatches = status?['connected'] as int? ?? 0;
        _missingWatches = missing;
        _watchCheckError = null;
        _checkingWatches = false;
      });
    } on PlatformException {
      if (mounted) {
        setState(() {
          _watchCheckError = T('i18n.could_not_check_the_watch');
          _checkingWatches = false;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _watchCheckError = T('i18n.watch_installation_guidance_is_unavailable');
          _checkingWatches = false;
        });
      }
    }
  }

  Future<void> _openWatchStore(String nodeId) async {
    if (_openingStore) return;
    setState(() => _openingStore = true);
    String message;
    try {
      await _companion.invokeMethod<void>('openWatchStore', {'nodeId': nodeId});
      message = T('i18n.requested_the_installation_page');
    } on PlatformException {
      message = T('i18n.watch_install_page_failed_hint');
    } catch (_) {
      message = T('i18n.could_not_open_the_installation');
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.install_watch_app')),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: Text(T('i18n.confirm')),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    if (mounted) _checkWatches();
  }

  String get _watchStatus {
    if (_checkingWatches) return T('i18n.checking_connected_watches');
    if (_watchCheckError != null) return _watchCheckError!;
    if (_isAppleWatch) {
      if (_connectedWatches == 0) return T('i18n.no_apple_watch_paired');
      if (!_watchAppInstalled) return T('i18n.ai_link_is_not_installed');
      return _watchReachable ? T('i18n.apple_watch_connected') : T('i18n.watch_app_installed_waiting');
    }
    if (_connectedWatches == 0) return T('i18n.wear_os_data_connection');
    if (_missingWatches.isNotEmpty) {
      return T('i18n.a_connected_watch_needs');
    }
    return T('i18n.app_installed_on_all_connected');
  }

  Future<void> _load() async {
    final store = ChatStore.instance;
    final providers = await store.providers();
    final selection = await loadWatchChatSelection(store);
    final selected =
        providers.where((p) => p.id == selection?.providerId).firstOrNull ??
        providers.firstOrNull;
    final model = selected != null && selected.id == selection?.providerId
        ? selection!.model
        : selected?.model;
    final speak = await store.setting('watch_tts_enabled') == '1';
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _providerId = selected?.id;
      _model = model;
      _speak = speak;
    });
  }

  Future<void> _chooseModel() async {
    if (_providers.isEmpty) return;
    final selected = await Navigator.push<ChatModelSelection>(
      context,
      appPageRoute(
        builder: (_) => ChatModelSelector(
          providers: _providers,
          topics: const [],
          providerId: _providerId,
          model: _model,
          loadModels: (provider) async {
            final key = await ChatStore.instance.apiKey(provider.id);
            if (key == null || key.isEmpty) {
              throw ApiException(T('i18n.enter_api_key_in_settings'));
            }
            final models = await ModelApiClient(provider, key).fetchModels();
            if (models.isNotEmpty) {
              await ChatStore.instance.saveModelCache(provider, models);
            }
            return models;
          },
          loadCachedModels: ChatStore.instance.cachedModels,
        ),
      ),
    );
    if (selected == null) return;
    final store = ChatStore.instance;
    await store.saveWatchChatSelection(
      ChatSelection(selected.providerId, selected.model),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.watch'),
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
              _isAppleWatch
                  ? 'i18n.install_ai_link_for_apple'
                  : 'i18n.after_bluetooth_pairing_finish_connecting',
            ),
            children: [
              IosRow(
                title: T('i18n.watch_companion_app'),
                subtitle: _watchStatus,
                leading: Icon(
                  CupertinoIcons.device_phone_portrait,
                  color: IosColors.blue,
                ),
                trailing: _checkingWatches
                    ? const CupertinoActivityIndicator()
                    : null,
                onTap: _checkWatches,
              ),
              for (final (id, name)
                  in _isAppleWatch ? <(String, String)>[] : _missingWatches)
                IosRow(
                  title: T('i18n.install_on_watch'),
                  subtitle: name,
                  leading: Icon(
                    CupertinoIcons.arrow_down_circle,
                    color: IosColors.blue,
                  ),
                  onTap: _openingStore ? null : () => _openWatchStore(id),
                ),
            ],
          ),
          IosSection(
            footer: T(
              _isAppleWatch
                  ? 'i18n.apple_watch_requests_voice'
                  : 'i18n.use_the_phone_network_first',
            ),
            children: [
              IosRow(
                title: T('i18n.watch_model'),
                subtitle: _providerId == null
                    ? T('i18n.configure_a_model_provider_first')
                    : '${_providers.where((p) => p.id == _providerId).first.name} · ${_model ?? ''}',
                leading: Icon(
                  CupertinoIcons.square_stack,
                  color: IosColors.blue,
                ),
                onTap: _chooseModel,
              ),
              IosRow(
                title: T('i18n.speak_replies_on_watch'),
                chevron: false,
                trailing: CupertinoSwitch(
                  value: _speak,
                  onChanged: (value) async {
                    await ChatStore.instance.saveSetting(
                      'watch_tts_enabled',
                      value ? '1' : '0',
                    );
                    if (mounted) setState(() => _speak = value);
                  },
                ),
              ),
            ],
          ),
          IosSection(
            footer: T(
              'i18n.voice_transcription_setup_hint',
            ),
            children: [
              IosRow(
                title: T('i18n.voice_services'),
                leading: Icon(CupertinoIcons.waveform, color: IosColors.blue),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(builder: (_) => const VoiceSettingsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
