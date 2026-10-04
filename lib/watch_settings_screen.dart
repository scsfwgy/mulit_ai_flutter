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
          _watchCheckError = tr('无法检查手表数据连接，请稍后重试');
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
    if (_isAppleWatch) {
      if (_connectedWatches == 0) return tr('尚未配对 Apple Watch');
      if (!_watchAppInstalled) return tr('Apple Watch 尚未安装 AI Link');
      return _watchReachable ? tr('Apple Watch 已连接') : tr('手表应用已安装，等待连接');
    }
    if (_connectedWatches == 0) return tr('尚未建立 Wear OS 数据连接');
    if (_missingWatches.isNotEmpty) {
      return tr('有手表尚未安装应用');
    }
    return tr('已连接的手表均已安装应用');
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
    await store.saveWatchChatSelection(
      ChatSelection(selected.providerId, selected.model),
    );
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
              _isAppleWatch
                  ? '在 iPhone 的 Watch 应用中安装 AI Link 手表版。首次使用请先在手机端配置文字和语音服务；手表与手机配对并连接后，点上方状态重新检查。'
                  : '蓝牙配对后，还需完成 Wear OS 配套应用的连接设置。模拟器请使用 Android Studio 的 Pair Wearable；完成后点上方状态重新检查。商店暂无本应用时，请从原安装渠道获取手表版。',
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
              for (final (id, name)
                  in _isAppleWatch ? <(String, String)>[] : _missingWatches)
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
              _isAppleWatch
                  ? 'Apple Watch 优先在手表请求语音和模型服务，手表网络不可用且手机可达时再交给 iPhone。所选密钥同步并保存在手表钥匙串；问答在手表保存，重连后同步到手机。明确且可安全重试的网络故障才换路，超时或已有部分回答时不重发。'
                  : '已连接手机时优先使用手机网络，失败后尝试手表网络；未连接时先用手表 Wi-Fi 或蜂窝网络。仅明确的网络故障才自动换路，避免重复请求。配置与密钥由手机同步到手表。',
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
