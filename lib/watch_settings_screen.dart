import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

class _WatchSettingsScreenState extends State<WatchSettingsScreen> {
  List<ProviderConfig> _providers = [];
  int? _providerId;
  String? _model;
  bool _speak = false;

  @override
  void initState() {
    super.initState();
    _load();
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
            footer: tr('手表只录音、显示回复和播放音频。语音识别、模型请求、会话记录和 API Key 都由配对的安卓手机处理。'),
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
