import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_preferences.dart';
import 'data.dart';
import 'ios_style.dart';
import 'search_service.dart';

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
          _error = tr('无法读取搜索配置，请重试。');
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([SearchProviderConfig? service]) async {
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(builder: (_) => SearchServiceEditor(service: service)),
    );
    await _load();
  }

  Future<void> _select() async {
    final value = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('默认搜索服务')),
        actions: [
          for (final service in _services)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, service.id),
              child: Text(service.name),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, ''),
            child: Text(tr('不使用')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(tr('取消')),
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
      if (mounted) _showError(context, tr('无法保存搜索配置，请重试。'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: tr('联网搜索'),
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
                  footer: tr('开启联网后，先搜索网页，再由当前文本模型回答。联网设置会自动同步到配对手表。'),
                  children: [
                    IosRow(
                      title: '默认搜索服务',
                      subtitle:
                          _services
                              .where((item) => item.id == _selectedId)
                              .firstOrNull
                              ?.name ??
                          tr('未设置'),
                      leading: Icon(
                        CupertinoIcons.globe,
                        color: IosColors.blue,
                      ),
                      onTap: _select,
                    ),
                  ],
                ),
                IosSection(
                  title: '搜索服务',
                  footer: tr(
                    '搜索服务只需独立 API Key，无需模型 ID。查询直接发送到所选搜索服务，检索资料随后发送给文本模型；搜索和模型请求可能分别计费。',
                  ),
                  children: [
                    for (final service in _services)
                      IosRow(
                        title: service.name,
                        subtitle: service.service.label,
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
                      title: '添加搜索服务',
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
    _name = TextEditingController(text: saved?.name ?? _service.label);
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

  Future<T?> _choose<T>(String title, Map<T, String> options) =>
      showCupertinoModalPopup<T>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(tr(title)),
          actions: [
            for (final option in options.entries)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(sheetContext, option.key),
                child: Text(tr(option.value)),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(tr('取消')),
          ),
        ),
      );

  Future<void> _chooseService() async {
    final selected = await _choose('搜索服务类型', {
      for (final value in SearchService.values) value: value.label,
    });
    if (selected == null || !mounted || selected == _service) return;
    setState(() {
      if (_name.text == _service.label) _name.text = selected.label;
      _service = selected;
      _endpoint.text = selected.endpoint;
      _key.clear();
      _detailed = false;
    });
  }

  SearchProviderConfig _config() {
    if (_name.text.trim().isEmpty) throw const FormatException('请填写服务名称');
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
      throw const FormatException('API Key 不能包含换行或控制字符');
    }
    if (provided.isNotEmpty) return provided;
    final saved = widget.service;
    if (saved != null &&
        saved.service == config.service &&
        saved.endpoint == config.endpoint) {
      final existing = await ChatStore.instance.searchApiKey(saved.id);
      if (existing?.isNotEmpty == true) return existing!;
    }
    throw const FormatException('请填写搜索服务 API Key；更换服务类型或地址时须重新填写。');
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
          error is FormatException ? tr(error.message) : tr('无法保存搜索配置，请重试。'),
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
      if (mounted) _showError(context, tr('搜索成功，配置可用。'), title: '测试搜索');
    } catch (error) {
      if (mounted) {
        _showError(
          context,
          error is FormatException
              ? tr(error.message)
              : error is SearchException
              ? tr(error.message)
              : tr('测试搜索失败，请检查配置。'),
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
          title: Text(tr('无法打开浏览器')),
          content: SelectableText(url),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(tr('复制网址')),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('好')),
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
        title: Text(tr('删除搜索服务？')),
        content: Text(tr('同时删除其密钥；历史消息中的搜索来源保留。')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('取消')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('删除')),
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
      if (mounted) _showError(context, tr('无法删除搜索服务，请重试。'));
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
          tr(label),
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
      title: tr(widget.service == null ? '添加搜索服务' : '编辑搜索服务'),
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
            footer: tr('接口地址自动填写；修改为代理地址时，请确认可信并重新填写密钥。'),
            children: [
              IosRow(
                title: '搜索服务类型',
                subtitle: _service.label,
                onTap: _busy ? null : _chooseService,
              ),
              _field('服务名称', _name),
              _field('搜索接口地址', _endpoint),
              _field(
                widget.service == null ? 'API Key' : 'API Key（留空保留原密钥）',
                _key,
                secret: true,
              ),
            ],
          ),
          IosSection(
            title: '申请与费用',
            footer:
                '${tr(_service.billingDescription)}\n${tr('免费额度和价格可能调整，以官网及账号实际额度为准。搜索与文本模型分别计费。')}',
            children: [
              IosRow(
                title: '申请 API Key',
                subtitle: _service.apiKeyUrl.replaceFirst('https://', ''),
                leading: Icon(CupertinoIcons.globe, color: IosColors.blue),
                onTap: _busy
                    ? null
                    : () => _openProviderPage(_service.apiKeyUrl),
              ),
              IosRow(
                title: '查看价格与免费额度',
                subtitle: _service.billingLabel,
                leading: Icon(
                  CupertinoIcons.money_dollar_circle,
                  color: IosColors.blue,
                ),
                onTap: _busy
                    ? null
                    : () => _openProviderPage(_service.pricingUrl),
              ),
            ],
          ),
          IosSection(
            title: '搜索选项',
            footer: tr('更多结果和深入搜索可能增加费用与等待时间。'),
            children: [
              IosRow(
                title: '结果数量',
                subtitle: '$_count',
                onTap: _busy
                    ? null
                    : () async {
                        final value = await _choose('结果数量', {
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
                title: '时间范围',
                subtitle: searchRangeLabel(_range),
                onTap: _busy
                    ? null
                    : () async {
                        final value = await _choose('时间范围', {
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
                  title: '深入搜索',
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
            footer: tr('测试会向搜索服务发送“Flutter”，可能产生搜索费用；不会保存配置。'),
            children: [
              IosRow(
                title: _busy ? '请稍候…' : '测试搜索',
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
                  title: '删除搜索服务',
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

String searchRangeLabel(SearchTimeRange range) => switch (range) {
  SearchTimeRange.any => '不限时间',
  SearchTimeRange.day => '最近一天',
  SearchTimeRange.week => '最近一周',
  SearchTimeRange.month => '最近一个月',
  SearchTimeRange.year => '最近一年',
};

void _showError(BuildContext context, String message, {String title = '提示'}) {
  showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(tr(title)),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(tr('好')),
        ),
      ],
    ),
  );
}
