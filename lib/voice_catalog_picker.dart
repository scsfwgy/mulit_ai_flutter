import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';
import 'ios_style.dart';
import 'voice_catalog.dart';

class VoiceCatalogPicker extends StatefulWidget {
  const VoiceCatalogPicker({
    super.key,
    required this.title,
    required this.examples,
    this.initialValue,
    this.onRefresh,
  });

  final String title;
  final List<VoiceCatalogOption> examples;
  final String? initialValue;
  final Future<List<VoiceCatalogOption>> Function()? onRefresh;

  @override
  State<VoiceCatalogPicker> createState() => _VoiceCatalogPickerState();
}

class _VoiceCatalogPickerState extends State<VoiceCatalogPicker> {
  List<VoiceCatalogOption>? _remote;
  bool _loading = false;
  String? _error;
  String _query = '';

  Future<void> _enterManually() async {
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _ManualVoiceIdDialog(initialValue: widget.initialValue),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  @override
  void initState() {
    super.initState();
    if (widget.onRefresh != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  Future<void> _refresh() async {
    if (_loading || widget.onRefresh == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.onRefresh!();
      if (mounted) setState(() => _remote = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '无法获取模型列表，请检查网络或手动填写',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = _remote ?? const <VoiceCatalogOption>[];
    final remoteIds = remote.map((item) => item.id).toSet();
    final examples = widget.examples.where(
      (item) => !remoteIds.contains(item.id),
    );
    bool matches(VoiceCatalogOption item) =>
        item.id.toLowerCase().contains(_query.toLowerCase()) ||
        (item.name?.toLowerCase().contains(_query.toLowerCase()) ?? false);
    final visibleRemote = remote.where(matches).toList();
    final visibleExamples = examples.where(matches).toList();
    return Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: widget.title,
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
        actions: widget.onRefresh == null
            ? null
            : [
                CupertinoButton(
                  onPressed: _loading ? null : _refresh,
                  child: _loading
                      ? const CupertinoActivityIndicator()
                      : Icon(CupertinoIcons.refresh, color: IosColors.blue),
                ),
              ],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: CupertinoSearchTextField(
                placeholder: tr('搜索 ID 或名称'),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 12, 30, 0),
                child: Text(
                  tr(_error!),
                  style: TextStyle(color: IosColors.destructive),
                ),
              ),
            if (visibleRemote.isNotEmpty)
              IosSection(
                title: '服务端返回',
                footer: '模型列表仅包含服务端返回的 ID，语音接口和账号权限仍需实际验证。',
                children: [
                  for (final item in visibleRemote)
                    IosRow(
                      title: item.id,
                      subtitle: item.name == null ? null : tr(item.name!),
                      onTap: () => Navigator.pop(context, item.id),
                    ),
                ],
              ),
            if (visibleExamples.isNotEmpty)
              IosSection(
                title: '官方示例',
                footer: widget.onRefresh == null
                    ? '此服务没有可用的 API Key 列表接口。示例不代表账号已开通；也可返回手动填写。'
                    : '示例来自官方文档，不代表当前账号已开通；也可返回手动填写。',
                children: [
                  for (final item in visibleExamples)
                    IosRow(
                      title: item.id,
                      subtitle: item.name == null ? null : tr(item.name!),
                      onTap: () => Navigator.pop(context, item.id),
                    ),
                ],
              ),
            if (visibleRemote.isEmpty && visibleExamples.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  tr('没有匹配的模型'),
                  style: TextStyle(color: IosColors.secondary),
                ),
              ),
            IosSection(
              children: [
                IosRow(
                  title: '手动输入 ID',
                  leading: Icon(CupertinoIcons.pencil, color: IosColors.blue),
                  onTap: _enterManually,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ManualVoiceIdDialog extends StatefulWidget {
  const _ManualVoiceIdDialog({this.initialValue});
  final String? initialValue;

  @override
  State<_ManualVoiceIdDialog> createState() => _ManualVoiceIdDialogState();
}

class _ManualVoiceIdDialogState extends State<_ManualVoiceIdDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useId() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: Text(tr('手动输入 ID')),
    content: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CupertinoTextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        maxLength: 160,
        placeholder: tr('输入模型或音色 ID'),
        onSubmitted: (_) => _useId(),
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('取消')),
      ),
      CupertinoDialogAction(onPressed: _useId, child: Text(tr('使用此 ID'))),
    ],
  );
}
