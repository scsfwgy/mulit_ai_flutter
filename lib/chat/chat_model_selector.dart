import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/storefront_policy.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/chat/model_picker.dart';

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

class _ChatModelSelectorState extends State<ChatModelSelector> with StorefrontAware {
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
        throw ApiException(T('i18n.no_usable_models_manual'));
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
        _error = F(
          _models.isNotEmpty
              ? 'i18n.model_list_refresh_failed_cached'
              : 'i18n.model_list_fetch_failed_manual',
          [error],
        );
      });
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _choose(String model) async {
    try {
      await StorefrontPolicy.instance.requireAllowed(_provider.baseUrl, presetId: _provider.presetId, model: model);
      if (!mounted) return;
      Navigator.pop(context, ChatModelSelection(_providerId, model));
    } on StorefrontRestrictedException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  String? get _cacheSubtitle {
    final time = _fetchedAt;
    if (time == null) return null;
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return F(_fromCache ? 'i18n.cached_at' : 'i18n.updated_at', ['$date $clock']);
  }

  void _useManual() {
    final model = _model.text.trim();
    if (model.isEmpty) {
      setState(() => _error = T('i18n.enter_model_id_prompt'));
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
        title: T('i18n.switch_model'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            IosSection(
              title: T('i18n.model_services'),
              children: [
                for (final provider in widget.providers.where((p) => !StorefrontPolicy.instance.blocks(p.baseUrl, presetId: p.presetId, model: p.model)))
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
                title: T('i18n.recently_used'),
                children: [
                  for (final model in recent)
                    IosRow(title: model, onTap: () => _choose(model)),
                ],
              ),
            IosSection(
              title: T('i18n.enter_a_model_id'),
              footer: T('i18n.you_can_use_a_model'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: CupertinoTextField(
                    controller: _model,
                    placeholder: F('i18n.model_id_example', [_provider.model]),
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
              child: IosPrimaryButton(label: T('i18n.use_this_model'), onPressed: _useManual),
            ),
            IosSection(
              title: T('i18n.server_models'),
              children: [
                IosRow(
                  title: _fetching
                      ? T('i18n.fetching_models')
                      : _models.isNotEmpty
                      ? T('i18n.refresh_model_list')
                      : T('i18n.fetch_models_from_server'),
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
                  T(_error!),
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
                  placeholder: T('i18n.search_model_id'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              ModelCatalog(
                models: _models.where((id) => !(StorefrontPolicy.instance.restricted && StorefrontPolicy.isOpenAIModel(id))).toList(),
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
