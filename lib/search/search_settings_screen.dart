import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/provider/api_key_help.dart';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

class SearchSettingsScreen extends StatefulWidget {
  const SearchSettingsScreen({super.key});
  @override
  State<SearchSettingsScreen> createState() => _SearchSettingsScreenState();
}

class _SearchSettingsScreenState extends State<SearchSettingsScreen> {
  List<SearchProviderConfig> _services = [];
  String? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final services = await ChatStore.instance.searchProviders();
      final selected = await ChatStore.instance.setting('search_provider_id');
      if (mounted) {
        setState(() {
          _services = services;
          _selectedId = selected;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = T('i18n.could_not_read_search_settings');
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([SearchProviderConfig? service]) async {
    await Navigator.push<void>(
      context,
      appPageRoute(builder: (_) => SearchServiceEditor(service: service)),
    );
    await _load();
  }

  Future<void> _select() async {
    final value = await showAppModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(T('i18n.default_search_service')),
        actions: [
          for (final service in _services)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, service.id),
              child: Text(service.name),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ''),
            child: Text(T('i18n.none')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (value == null) return;
    try {
      await ChatStore.instance.saveSetting('search_provider_id', value);
      if (value.isEmpty) {
        await ChatStore.instance.saveSetting('search_enabled', '0');
      }
      await _load();
    } catch (_) {
      if (mounted) _showError(context, T('i18n.could_not_save_search_settings'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.web_search'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              children: [
                if (_error != null)
                  IosSection(
                    children: [IosRow(title: _error!, onTap: _load)],
                  ),
                IosSection(
                  footer: T('i18n.when_enabled_web_search_runs'),
                  children: [
                    IosRow(
                      title: T('i18n.default_search_service'),
                      subtitle:
                          _services
                              .where((item) => item.id == _selectedId)
                              .firstOrNull
                              ?.name ??
                          T('i18n.not_set'),
                      leading: Icon(
                        CupertinoIcons.globe,
                        color: IosColors.blue,
                      ),
                      onTap: _select,
                    ),
                  ],
                ),
                IosSection(
                  title: T('i18n.search_services'),
                  footer: T(
                    'i18n.search_services_need_their_own',
                  ),
                  children: [
                    for (final service in _services)
                      IosRow(
                        title: service.name,
                        subtitle: T(service.service.label),
                        leading: Icon(
                          CupertinoIcons.search,
                          color: IosColors.blue,
                        ),
                        trailing: service.id == _selectedId
                            ? Icon(
                                CupertinoIcons.check_mark,
                                color: IosColors.blue,
                                size: 18,
                              )
                            : null,
                        onTap: () => _edit(service),
                      ),
                    IosRow(
                      title: T('i18n.add_search_service'),
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

class SearchServiceEditor extends StatefulWidget {
  const SearchServiceEditor({super.key, this.service});
  final SearchProviderConfig? service;
  @override
  State<SearchServiceEditor> createState() => _SearchServiceEditorState();
}

class _SearchServiceEditorState extends State<SearchServiceEditor> {
  late SearchService _service;
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  final _key = TextEditingController();
  late int _count;
  late bool _detailed;
  late SearchTimeRange _range;
  bool _busy = false;
  bool _obscure = true;
  SearchClient? _testClient;

  @override
  void initState() {
    super.initState();
    final saved = widget.service;
    _service = saved?.service ?? SearchService.bocha;
    _name = TextEditingController(text: saved?.name ?? T(_service.label));
    _endpoint = TextEditingController(
      text: saved?.endpoint ?? _service.endpoint,
    );
    _count = saved?.maxResults ?? 5;
    _detailed = saved?.detailed ?? false;
    _range = saved?.timeRange ?? SearchTimeRange.any;
  }

  @override
  void dispose() {
    _testClient?.cancel();
    for (final controller in [_name, _endpoint, _key]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<TValue?> _choose<TValue>(String title, Map<TValue, String> options) =>
      showAppModalPopup<TValue>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(T(title)),
          actions: [
            for (final option in options.entries)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(sheetContext, option.key),
                child: Text(T(option.value)),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(T('i18n.cancel')),
          ),
        ),
      );

  Future<void> _chooseService() async {
    final selected = await _choose('i18n.search_provider', {
      for (final value in SearchService.values) value: value.label,
    });
    if (selected == null || !mounted || selected == _service) return;
    setState(() {
      if (_name.text == T(_service.label)) _name.text = T(selected.label);
      _service = selected;
      _endpoint.text = selected.endpoint;
      _key.clear();
      _detailed = false;
    });
  }

  SearchProviderConfig _config() {
    if (_name.text.trim().isEmpty) throw FormatException(T('i18n.enter_a_service_name'));
    return SearchProviderConfig(
      id:
          widget.service?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      service: _service,
      endpoint: validateBaseUrl(_endpoint.text),
      maxResults: _count,
      detailed: _detailed,
      timeRange: _range,
    );
  }

  Future<String> _apiKey(SearchProviderConfig config) async {
    final provided = _key.text.trim();
    if (provided.contains(RegExp(r'[\x00-\x1F]'))) {
      throw FormatException(T('i18n.api_keys_cannot_contain_line'));
    }
    if (provided.isNotEmpty) return provided;
    final saved = widget.service;
    if (saved != null &&
        saved.service == config.service &&
        saved.endpoint == config.endpoint) {
      final existing = await ChatStore.instance.searchApiKey(saved.id);
      if (existing?.isNotEmpty == true) return existing!;
    }
    throw FormatException(T('i18n.enter_the_search_api_key'));
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final config = _config();
      await _apiKey(config);
      await ChatStore.instance.saveSearchProvider(config, apiKey: _key.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        _showError(
          context,
          error is FormatException ? T(error.message) : T('i18n.could_not_save_search_settings'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final config = _config();
      final key = await _apiKey(config);
      if (!mounted) return;
      _testClient = SearchClient(config, key);
      await _testClient!.search('Flutter');
      if (mounted) _showError(context, T('i18n.search_succeeded_the_configuration_works'), title: T('i18n.test_search'));
    } catch (error) {
      if (mounted) {
        _showError(
          context,
          error is FormatException
              ? T(error.message)
              : error is SearchException
              ? T(error.message)
              : T('i18n.search_test_failed_check'),
        );
      }
    } finally {
      _testClient?.cancel();
      _testClient = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openProviderPage(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep the official URL available if no browser can handle the request.
    }
    if (mounted) {
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(T('i18n.could_not_open_a_browser')),
          content: SelectableText(url),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(T('i18n.copy_url')),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(T('i18n.ok')),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _delete() async {
    if (_busy || widget.service == null) return;
    final approved = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(T('i18n.delete_search_service_confirm')),
        content: Text(T('i18n.its_key_will_also')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(T('i18n.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(T('i18n.delete')),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ChatStore.instance.deleteSearchProvider(widget.service!.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) _showError(context, T('i18n.could_not_delete_the_search'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.all(14),
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
          enabled: !_busy,
          obscureText: secret && _obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: controller == _endpoint
              ? TextInputType.url
              : TextInputType.text,
          style: TextStyle(color: IosColors.label),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: IosColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          suffix: secret
              ? CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  child: Icon(
                    _obscure ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    color: IosColors.secondary,
                    size: 20,
                  ),
                )
              : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T(widget.service == null ? 'i18n.add_search_service' : 'i18n.edit_search_service'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        _busy
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CupertinoActivityIndicator(),
              )
            : IosNavButton(icon: CupertinoIcons.check_mark, onPressed: _save),
      ],
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            footer: T('i18n.the_endpoint_is_filled_automatically'),
            children: [
              IosRow(
                title: T('i18n.search_provider'),
                subtitle: T(_service.label),
                onTap: _busy ? null : _chooseService,
              ),
              _field('i18n.service_name', _name),
              _field('i18n.search_endpoint', _endpoint),
              _field(
                widget.service == null
                    ? 'API Key'
                    : 'i18n.api_key_blank_keeps_current',
                _key,
                secret: true,
              ),
            ],
          ),
          IosSection(
            title: T('i18n.api_key_pricing'),
            footer:
                '${T(_service.billingDescription)}\n${T('i18n.free_credits_and_prices_may')}',
            children: [
              IosRow(
                title: T('i18n.get_an_api_key'),
                subtitle: _service.apiKeyUrl.replaceFirst('https://', ''),
                leading: Icon(CupertinoIcons.globe, color: IosColors.blue),
                onTap: _busy
                    ? null
                    : () => _openProviderPage(_service.apiKeyUrl),
              ),
              IosRow(
                title: T('i18n.pricing_free_credits'),
                subtitle: T(_service.billingLabel),
                leading: Icon(
                  CupertinoIcons.money_dollar_circle,
                  color: IosColors.blue,
                ),
                onTap: _busy
                    ? null
                    : () => _openProviderPage(_service.pricingUrl),
              ),
              ApiKeyHelpRow(url: '$apiKeyTutorialUrl#search', enabled: !_busy),
            ],
          ),
          IosSection(
            title: T('i18n.search_options'),
            footer: T('i18n.more_results_and_detailed_search'),
            children: [
              IosRow(
                title: T('i18n.result_count'),
                subtitle: '$_count',
                onTap: _busy
                    ? null
                    : () async {
                        final value = await _choose('i18n.result_count', {
                          3: '3',
                          5: '5',
                          10: '10',
                        });
                        if (value != null && mounted) {
                          setState(() => _count = value);
                        }
                      },
              ),
              IosRow(
                title: T('i18n.time_range'),
                subtitle: T(searchRangeLabel(_range)),
                onTap: _busy
                    ? null
                    : () async {
                        final value = await _choose('i18n.time_range', {
                          for (final range in SearchTimeRange.values)
                            range: searchRangeLabel(range),
                        });
                        if (value != null && mounted) {
                          setState(() => _range = value);
                        }
                      },
              ),
              if (_service != SearchService.bocha)
                IosRow(
                  title: T('i18n.detailed_search'),
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: _detailed,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _detailed = value),
                  ),
                ),
            ],
          ),
          IosSection(
            footer: T('i18n.testing_sends_flutter'),
            children: [
              IosRow(
                title: _busy ? T('i18n.please_wait') : T('i18n.test_search'),
                chevron: false,
                leading: _busy
                    ? const CupertinoActivityIndicator()
                    : Icon(CupertinoIcons.search, color: IosColors.blue),
                onTap: _busy ? null : _test,
              ),
            ],
          ),
          if (widget.service != null)
            IosSection(
              children: [
                IosRow(
                  title: T('i18n.delete_search_service'),
                  chevron: false,
                  leading: Icon(
                    CupertinoIcons.trash,
                    color: IosColors.destructive,
                  ),
                  onTap: _busy ? null : _delete,
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

/// 返回文案 key；调用方统一经 [T] 解析。
String searchRangeLabel(SearchTimeRange range) => switch (range) {
  SearchTimeRange.any => 'i18n.any_time',
  SearchTimeRange.day => 'i18n.past_day',
  SearchTimeRange.week => 'i18n.past_week',
  SearchTimeRange.month => 'i18n.past_month',
  SearchTimeRange.year => 'i18n.past_year',
};

void _showError(BuildContext context, String message, {String title = 'i18n.hint'}) {
  showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(T(title)),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(T('i18n.ok')),
        ),
      ],
    ),
  );
}
