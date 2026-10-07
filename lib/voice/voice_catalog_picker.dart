import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/voice/voice_catalog.dart';

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
              : T('i18n.model_list_unavailable_manual'),
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
                placeholder: T('i18n.search_id_or_name'),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 12, 30, 0),
                child: Text(
                  T(_error!),
                  style: TextStyle(color: IosColors.destructive),
                ),
              ),
            if (visibleRemote.isNotEmpty)
              IosSection(
                title: T('i18n.returned_by_server'),
                footer: T('i18n.the_server_returned_these_ids'),
                children: [
                  for (final item in visibleRemote)
                    IosRow(
                      title: item.id,
                      subtitle: item.name == null ? null : T(item.name!),
                      onTap: () => Navigator.pop(context, item.id),
                    ),
                ],
              ),
            if (visibleExamples.isNotEmpty)
              IosSection(
                title: T('i18n.official_examples'),
                footer: widget.onRefresh == null
                    ? T('i18n.no_api_key_catalog')
                    : T('i18n.examples_come_from_official_docs'),
                children: [
                  for (final item in visibleExamples)
                    IosRow(
                      title: item.id,
                      subtitle: item.name == null ? null : T(item.name!),
                      onTap: () => Navigator.pop(context, item.id),
                    ),
                ],
              ),
            if (visibleRemote.isEmpty && visibleExamples.isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  T('i18n.no_matching_models'),
                  style: TextStyle(color: IosColors.secondary),
                ),
              ),
            IosSection(
              children: [
                IosRow(
                  title: T('i18n.enter_an_id_manually'),
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
    title: Text(T('i18n.enter_an_id_manually')),
    content: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CupertinoTextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        maxLength: 160,
        placeholder: T('i18n.enter_a_model_or_voice'),
        onSubmitted: (_) => _useId(),
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: Text(T('i18n.cancel')),
      ),
      CupertinoDialogAction(onPressed: _useId, child: Text(T('i18n.use_this_id'))),
    ],
  );
}
