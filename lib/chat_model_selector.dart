import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'data.dart';
import 'app_preferences.dart';
import 'ios_style.dart';
import 'model_picker.dart';

typedef ModelListLoader = Future<List<String>> Function(
  ProviderConfig provider,
);
typedef CachedModelListLoader = Future<CachedModelList?> Function(
  ProviderConfig provider,
);

class ChatModelSelection {
  const ChatModelSelection(this.providerId, this.model);

  final int providerId;
  final String model;
}

class ChatModelSelector extends StatefulWidget {
  const ChatModelSelector({
    super.key,
    required this.providers,
    required this.topics,
    required this.providerId,
    required this.model,
    required this.loadModels,
    this.loadCachedModels,
  });

  final List<ProviderConfig> providers;
  final List<ChatTopic> topics;
  final int? providerId;
  final String? model;
  final ModelListLoader loadModels;
  final CachedModelListLoader? loadCachedModels;

  @override
  State<ChatModelSelector> createState() => _ChatModelSelectorState();
}

class _ChatModelSelectorState extends State<ChatModelSelector> {
  late int _providerId;
  late final TextEditingController _model;
  final _search = TextEditingController();
  List<String> _models = [];
  bool _loaded = false;
  bool _fetching = false;
  DateTime? _fetchedAt;
  bool _fromCache = false;
  String? _error;
  int _cacheGeneration = 0;

  ProviderConfig get _provider =>
      widget.providers.firstWhere((item) => item.id == _providerId);

  @override
  void initState() {
    super.initState();
    final selected = widget.providers
        .where((item) => item.id == widget.providerId)
        .firstOrNull;
    _providerId = selected?.id ?? widget.providers.first.id;
    _model = TextEditingController(
      text: selected == null ? _provider.model : widget.model ?? selected.model,
    );
    unawaited(_loadCache());
  }

  Future<void> _loadCache() async {
    final loader = widget.loadCachedModels;
    if (loader == null) return;
    final provider = _provider;
    final generation = ++_cacheGeneration;
    try {
      final cached = await loader(provider);
      if (!mounted ||
          generation != _cacheGeneration ||
          _providerId != provider.id ||
          _fetching ||
          cached == null ||
          !cached.matches(provider)) {
        return;
      }
      setState(() {
        _models = cached.models;
        _loaded = true;
        _fetchedAt = cached.fetchedAt;
        _fromCache = true;
      });
    } catch (_) {
      // A broken cache should not block manual entry or a fresh request.
    }
  }

  @override
  void dispose() {
    _model.dispose();
    _search.dispose();
    super.dispose();
  }

  void _selectProvider(ProviderConfig provider) {
    if (provider.id == _providerId || _fetching) return;
    setState(() {
      _providerId = provider.id;
      _model.text = provider.model;
      _search.clear();
      _models = [];
      _loaded = false;
      _fetchedAt = null;
      _fromCache = false;
      _error = null;
    });
    unawaited(_loadCache());
  }

  Future<void> _fetchModels() async {
    if (_fetching) return;
    _cacheGeneration++;
    final providerId = _providerId;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final models = await widget.loadModels(_provider);
      if (models.isEmpty) {
        throw const ApiException('服务没有返回可用模型，可手动输入模型 ID。');
      }
      if (!mounted || _providerId != providerId) return;
      setState(() {
        _models = models;
        _loaded = true;
        _fetchedAt = DateTime.now();
        _fromCache = false;
      });
    } catch (error) {
      if (!mounted || _providerId != providerId) return;
      setState(() {
        _error = _models.isNotEmpty
            ? (AppPreferences.instance.english
                  ? 'Refresh failed: $error\nThe cached models are still available.'
                  : '刷新失败：$error\n已保留缓存的模型列表。')
            : (AppPreferences.instance.english
                  ? 'Could not fetch models: $error\nYou can still enter a model ID.'
                  : '获取模型列表失败：$error\n仍可手动输入模型 ID。');
      });
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _choose(String model) =>
      Navigator.pop(context, ChatModelSelection(_providerId, model));

  String? get _cacheSubtitle {
    final time = _fetchedAt;
    if (time == null) return null;
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (AppPreferences.instance.english) {
      return '${_fromCache ? 'Cached' : 'Updated'} $date $clock';
    }
    return '${_fromCache ? '已缓存' : '更新于'} $date $clock';
  }

  void _useManual() {
    final model = _model.text.trim();
    if (model.isEmpty) {
      setState(() => _error = '请输入模型 ID');
      return;
    }
    _choose(model);
  }

  @override
  Widget build(BuildContext context) {
    final recent = widget.topics
        .where((topic) => topic.providerId == _providerId)
        .map((topic) => topic.model)
        .where((model) => model.isNotEmpty)
        .toSet()
        .take(5)
        .toList();
    return Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: '切换模型',
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            IosSection(
              title: '模型服务',
              children: [
                for (final provider in widget.providers)
                  IosRow(
                    title: provider.name,
                    leading: Icon(
                      CupertinoIcons.square_stack_3d_up,
                      color: provider.id == _providerId
                          ? IosColors.blue
                          : IosColors.secondary,
                      size: 21,
                    ),
                    trailing: provider.id == _providerId
                        ? Icon(
                            CupertinoIcons.check_mark,
                            color: IosColors.blue,
                            size: 21,
                          )
                        : null,
                    chevron: false,
                    onTap: () => _selectProvider(provider),
                  ),
              ],
            ),
            if (recent.isNotEmpty)
              IosSection(
                title: '最近使用',
                children: [
                  for (final model in recent)
                    IosRow(title: model, onTap: () => _choose(model)),
                ],
              ),
            IosSection(
              title: '手动输入模型 ID',
              footer: '可以使用未出现在服务端列表中的模型。',
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: CupertinoTextField(
                    controller: _model,
                    placeholder: AppPreferences.instance.english
                        ? 'e.g. ${_provider.model}'
                        : '例如 ${_provider.model}',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _useManual(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: IosPrimaryButton(label: '使用此模型', onPressed: _useManual),
            ),
            IosSection(
              title: '服务端模型',
              children: [
                IosRow(
                  title: _fetching
                      ? '正在获取模型列表…'
                      : _models.isNotEmpty
                      ? '刷新模型列表'
                      : '从服务端获取模型列表',
                  subtitle: _cacheSubtitle,
                  leading: _fetching
                      ? const CupertinoActivityIndicator()
                      : Icon(
                          _models.isNotEmpty
                              ? CupertinoIcons.refresh
                              : CupertinoIcons.arrow_down_circle,
                          color: IosColors.blue,
                          size: 22,
                        ),
                  onTap: _fetching ? null : _fetchModels,
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 10, 30, 0),
                child: Text(
                  tr(_error!),
                  style: TextStyle(
                    color: IosColors.destructive,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            if (_loaded && _models.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: CupertinoSearchTextField(
                  controller: _search,
                  placeholder: tr('搜索模型 ID'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ModelCatalog(
                models: _models,
                query: _search.text,
                onSelected: _choose,
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
