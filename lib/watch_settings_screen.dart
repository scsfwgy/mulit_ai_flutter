import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'app_preferences.dart';
import 'chat_model_selector.dart';
import 'data.dart';
import 'ios_style.dart';
import 'voice_settings_screen.dart';

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
        _connectedWatches = status?['connected'] as int? ?? 0;
        _missingWatches = missing;
        _watchCheckError = null;
        _checkingWatches = false;
      });
    } on PlatformException {
      if (mounted) {
        setState(() {
          _watchCheckError = tr('无法检查手表连接，请确认配对后重试');
          _checkingWatches = false;
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _watchCheckError = tr('此设备不支持手表安装引导');
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
      message = tr('已请求在手表打开安装页。若商店没有此应用，请从原安装渠道获取手表版。');
    } on PlatformException {
      message = tr('无法在手表打开安装页，请检查连接或手动安装');
    } catch (_) {
      message = tr('无法在手表打开安装页');
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('手表应用安装')),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: Text(tr('确定')),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    if (mounted) _checkWatches();
  }

  String get _watchStatus {
    if (_checkingWatches) return tr('正在检查已连接的手表…');
    if (_watchCheckError != null) return _watchCheckError!;
    if (_connectedWatches == 0) return tr('尚未连接 Wear OS 手表');
    if (_missingWatches.isNotEmpty) {
      return tr('有手表尚未安装应用');
    }
    return tr('已连接的手表均已安装应用');
  }

  Future<void> _load() async {
    final store = ChatStore.instance;
    final providers = await store.providers();
    final id = int.tryParse(await store.setting('watch_provider_id') ?? '');
    final selected =
        providers.where((p) => p.id == id).firstOrNull ?? providers.firstOrNull;
    final model = selected?.id == id
        ? await store.setting('watch_model_id') ?? selected?.model
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
      CupertinoPageRoute(
        builder: (_) => ChatModelSelector(
          providers: _providers,
          topics: const [],
          providerId: _providerId,
          model: _model,
          loadModels: (provider) async {
            final key = await ChatStore.instance.apiKey(provider.id);
            if (key == null || key.isEmpty) {
              throw const ApiException('请先在服务设置中填写 API Key');
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
    await store.saveSetting('watch_provider_id', '${selected.providerId}');
    await store.saveSetting('watch_model_id', selected.model);
    await store.saveSetting('watch_topic_id', '');
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: tr('手表'),
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
              '先将手表与安卓手机配对。连接后可在这里检查手表应用并打开安装页；商店暂无此应用时，请从原安装渠道获取手表版。',
            ),
            children: [
              IosRow(
                title: tr('配套手表应用'),
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
              for (final (id, name) in _missingWatches)
                IosRow(
                  title: tr('在手表安装'),
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
            footer: tr(
              '已连接手机时优先使用手机网络，失败后尝试手表网络；未连接时先用手表 Wi-Fi 或蜂窝网络。仅明确的网络故障才自动换路，避免重复请求。配置与密钥由手机同步到手表。',
            ),
            children: [
              IosRow(
                title: tr('手表使用的模型'),
                subtitle: _providerId == null
                    ? tr('请先配置模型服务')
                    : '${_providers.where((p) => p.id == _providerId).first.name} · ${_model ?? ''}',
                leading: Icon(
                  CupertinoIcons.square_stack,
                  color: IosColors.blue,
                ),
                onTap: _chooseModel,
              ),
              IosRow(
                title: tr('手表播报回复'),
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
            footer: tr(
              '在语音服务中选择识别服务，并设置转写后是否自动发送；该开关同时适用于手机和手表。开启播报时还需选择朗读服务。',
            ),
            children: [
              IosRow(
                title: tr('语音服务'),
                leading: Icon(CupertinoIcons.waveform, color: IosColors.blue),
                onTap: () => Navigator.push<void>(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const VoiceSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
