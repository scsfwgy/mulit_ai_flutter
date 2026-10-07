import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class ModelGroup {
  const ModelGroup(this.prefix, this.models);

  final String prefix;
  final List<String> models;
}

/// Groups large aggregator lists by vendor (`vendor/model`) or model family
/// (`claude-*`, `MiniMax-*`). Small or weakly prefixed lists stay flat.
List<ModelGroup>? groupModelsByPrefix(List<String> models) {
  if (models.length < 20) return null;
  final candidates = <String, List<String>>{};
  final labels = <String, String>{};
  final other = <String>[];
  for (final model in models) {
    final slash = model.indexOf('/');
    final hyphen = model.indexOf('-');
    final end = slash > 0 ? slash : hyphen;
    if (end < 2 || end == model.length - 1) {
      other.add(model);
      continue;
    }
    final prefix = model.substring(0, end);
    if (slash <= 0 &&
        !RegExp(r'^[\p{L}][\p{L}\p{N}_.]*$', unicode: true).hasMatch(prefix)) {
      other.add(model);
      continue;
    }
    final key = prefix.toLowerCase();
    labels.putIfAbsent(key, () => prefix);
    candidates.putIfAbsent(key, () => []).add(model);
  }
  final groups = candidates.entries
      .where((entry) => entry.value.length >= 3)
      .toList();
  final groupedCount = groups.fold<int>(
    0,
    (count, entry) => count + entry.value.length,
  );
  if (groupedCount < 8 ||
      (groups.length == 1 && groupedCount == models.length)) {
    return null;
  }
  final result =
      groups
          .map((entry) => ModelGroup(labels[entry.key]!, entry.value))
          .toList()
        ..sort(
          (a, b) => a.prefix.toLowerCase().compareTo(b.prefix.toLowerCase()),
        );
  final groupedNames = groups.map((entry) => entry.key).toSet();
  other.addAll([
    for (final entry in candidates.entries)
      if (!groupedNames.contains(entry.key)) ...entry.value,
  ]);
  if (other.isNotEmpty) result.add(ModelGroup('i18n.other_models', other..sort()));
  return result;
}

class ModelCatalog extends StatefulWidget {
  const ModelCatalog({
    super.key,
    required this.models,
    required this.query,
    required this.onSelected,
  });

  final List<String> models;
  final String query;
  final ValueChanged<String> onSelected;

  @override
  State<ModelCatalog> createState() => _ModelCatalogState();
}

class _ModelCatalogState extends State<ModelCatalog> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.models
        : widget.models
              .where((model) => model.toLowerCase().contains(query))
              .toList();
    final groups = query.isEmpty ? groupModelsByPrefix(widget.models) : null;
    if (groups == null) {
      final shown = filtered.take(100).toList();
      return IosSection(
        title: F('i18n.model_picker_title', [filtered.length]),
        footer: filtered.length > shown.length ? T('i18n.showing_the_first_100_results') : null,
        children: shown.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(T('i18n.no_matching_models')),
                ),
              ]
            : [
                for (final model in shown)
                  IosRow(title: model, onTap: () => widget.onSelected(model)),
              ],
      );
    }
    return IosSection(
      title: F('i18n.model_picker_title', [widget.models.length]),
      footer: T('i18n.grouped_by_service_or_model'),
      children: [
        for (final group in groups) ...[
          IosRow(
            title: T(group.prefix),
            subtitle: F('i18n.model_group_count', [group.models.length]),
            leading: Icon(
              CupertinoIcons.folder,
              color: IosColors.blue,
              size: 21,
            ),
            trailing: Icon(
              _expanded.contains(group.prefix)
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_right,
              color: IosColors.secondary,
              size: 16,
            ),
            chevron: false,
            onTap: () => setState(() {
              if (!_expanded.add(group.prefix)) _expanded.remove(group.prefix);
            }),
          ),
          if (_expanded.contains(group.prefix)) ...[
            for (final model in group.models.take(100))
              IosRow(
                title: model,
                leading: const SizedBox(width: 21),
                onTap: () => widget.onSelected(model),
              ),
            if (group.models.length > 100)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  T('i18n.group_showing_first_100'),
                  style: TextStyle(color: IosColors.secondary, fontSize: 13),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class ModelPicker extends StatefulWidget {
  const ModelPicker({
    super.key,
    required this.models,
    this.onRefresh,
    this.fetchedAt,
  });

  final List<String> models;
  final Future<List<String>> Function()? onRefresh;
  final DateTime? fetchedAt;

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  String query = '';
  late List<String> _models;
  DateTime? _fetchedAt;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _models = widget.models;
    _fetchedAt = widget.fetchedAt;
  }

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    if (refresh == null || _refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final models = await refresh();
      if (models.isEmpty) throw ApiException(T('i18n.the_service_returned_no_usable'));
      if (!mounted) return;
      setState(() {
        _models = models;
        _fetchedAt = DateTime.now();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.choose_model'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
      actions: widget.onRefresh == null
          ? null
          : [
              CupertinoButton(
                onPressed: _refreshing ? null : _refresh,
                child: _refreshing
                    ? const CupertinoActivityIndicator()
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.refresh,
                            color: IosColors.blue,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(T('i18n.refresh')),
                        ],
                      ),
              ),
            ],
    ),
    body: SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: CupertinoSearchTextField(
              placeholder: T('i18n.search_model_id'),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          if (_fetchedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 8, 20, 0),
              child: Text(
                F('i18n.model_cache_updated', [
                  '${_fetchedAt!.year}-${_fetchedAt!.month.toString().padLeft(2, '0')}'
                  '-${_fetchedAt!.day.toString().padLeft(2, '0')} '
                  '${_fetchedAt!.hour.toString().padLeft(2, '0')}'
                  ':${_fetchedAt!.minute.toString().padLeft(2, '0')}',
                ]),
                style: TextStyle(color: IosColors.secondary, fontSize: 12),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 8, 20, 0),
              child: Text(
                '${T('i18n.refresh_failed_the_current_list')} ${T(_error!)}',
                style: TextStyle(color: IosColors.destructive, fontSize: 13),
              ),
            ),
          ModelCatalog(
            models: _models,
            query: query,
            onSelected: (model) => Navigator.pop(context, model),
          ),
          const SizedBox(height: 30),
        ],
      ),
    ),
  );
}
