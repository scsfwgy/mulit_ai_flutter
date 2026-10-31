import 'package:mulit_ai_flutter/agent/agent_runner.dart';

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/ui/desktop_popup_menu.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/chat/project_screen.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class TopicScreen extends StatefulWidget {
  const TopicScreen({
    super.key,
    this.selectedId,
    this.generatingTopicId,
    this.persistent = false,
    this.revision,
    this.selection,
    this.onSearchSelect,
    this.onNewInProject,
    this.onChooseProject,
    required this.onClose,
    required this.onSelect,
    required this.onNew,
    required this.onSettings,
    required this.onChanged,
  });

  final Object? revision;
  final ProjectSelection? selection;
  final void Function(int topicId, int? messageId)? onSearchSelect;
  final ValueChanged<int?>? onNewInProject;
  final Future<ProjectSelection?> Function(bool moving)? onChooseProject;
  final int? selectedId;
  final int? generatingTopicId;
  final bool persistent;
  final VoidCallback onClose;
  final ValueChanged<int> onSelect;
  final VoidCallback onNew;
  final VoidCallback onSettings;
  final VoidCallback onChanged;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  List<ChatTopic> _topics = [];
  List<ChatProject> _projects = [];
  ProjectSelection _localSelection = const ProjectSelection(null);
  ProjectSelection get _selection => widget.selection ?? _localSelection;
  final _search = TextEditingController();
  Timer? _debounce;
  int _searchRevision = 0;
  List<HistoryMatch> _matches = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TopicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.selection != widget.selection) {
      _searchRevision++;
      _load();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = T('i18n.project_operation_failed'));
    }
  }

  Future<void> _searchHistory() async {
    final revision = ++_searchRevision;
    final query = _search.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _matches = [];
          _searching = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    try {
      final matches = await ChatStore.instance.searchHistory(
        query,
        projectId: _selection.id,
        ungrouped: _selection.ungrouped,
      );
      if (mounted && revision == _searchRevision) {
        setState(() {
          _matches = matches;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted && revision == _searchRevision) {
        setState(() {
          _searching = false;
          _error = T('i18n.project_operation_failed');
        });
      }
    }
  }

  Future<void> _chooseProject() async {
    final result = widget.onChooseProject != null
        ? await widget.onChooseProject!(false)
        : await Navigator.of(context).push<ProjectSelection>(
            appPageRoute(builder: (_) => const ProjectsScreen()),
          );
    if (!mounted) return;
    if (result != null && widget.selection == null) {
      setState(() => _localSelection = result);
    }
    await _load();
    widget.onChanged();
  }

  Future<void> _move(ChatTopic topic) async {
    if (topic.id == widget.generatingTopicId) return;
    final result = widget.onChooseProject != null
        ? await widget.onChooseProject!(true)
        : await Navigator.of(context).push<ProjectSelection>(
            appPageRoute(builder: (_) => const ProjectsScreen(moving: true)),
          );
    if (result == null) return;
    await ChatStore.instance.moveTopic(topic.id, result.id);
    await _load();
    widget.onChanged();
  }

  List<ChatTopic> get _visibleTopics => _topics
      .where(
        (t) => _selection.id != null
            ? t.projectId == _selection.id
            : !_selection.ungrouped || t.projectId == null,
      )
      .toList();

  List<ProviderConfig> _providers = [];
  Set<int> _watchTopicIds = {};
  Set<int> _searchedTopicIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final topics = await ChatStore.instance.topics();
    final projects = await ChatStore.instance.projects();
    final providers = await ChatStore.instance.providers();
    final watchTopicIds = await ChatStore.instance.watchTopicIds();
    final searchedTopicIds = await ChatStore.instance.searchedTopicIds();
    if (mounted) {
      setState(() {
        _topics = topics;
        _projects = projects;
        if (_selection.id != null &&
            !projects.any((p) => p.id == _selection.id)) {
          _localSelection = const ProjectSelection(null);
        }
        _providers = providers;
        _watchTopicIds = watchTopicIds;
        _searchedTopicIds = searchedTopicIds;
      });
    }
    if (mounted) await _searchHistory();
  }

  Widget _topicIcon(ChatTopic topic) {
    final isWatch = _watchTopicIds.contains(topic.id);
    final color = topic.id == widget.selectedId
        ? IosColors.blue
        : IosColors.secondary;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: Icon(
              isWatch ? Icons.watch_outlined : CupertinoIcons.chat_bubble_text,
              color: color,
              size: 22,
              semanticLabel: T(isWatch ? 'i18n.watch' : 'i18n.chats'),
            ),
          ),
          if (_searchedTopicIds.contains(topic.id))
            Positioned(
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: IosColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: Icon(
                    CupertinoIcons.globe,
                    color: color,
                    size: 13,
                    semanticLabel: T('i18n.web_search'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _actions(ChatTopic topic, BuildContext anchorContext) async {
    final entries = [
      DesktopPopupEntry(
        'pin',
        T(topic.pinnedAt > 0 ? 'i18n.unpin_chat' : 'i18n.pin_chat'),
        CupertinoIcons.pin,
      ),
      if (topic.id != widget.generatingTopicId)
        DesktopPopupEntry(
          'move',
          T('i18n.move_to_project'),
          CupertinoIcons.folder,
        ),
      DesktopPopupEntry('rename', T('i18n.rename'), CupertinoIcons.pencil),
      DesktopPopupEntry(
        'delete',
        T('i18n.delete_chat'),
        CupertinoIcons.trash,
        destructive: true,
      ),
    ];
    final action = isDesktopApp
        ? await showDesktopPopupMenu(context: anchorContext, entries: entries)
        : await showAppModalPopup<String>(
            context: context,
            builder: (context) => CupertinoActionSheet(
              title: Text(topic.title),
              actions: [
                for (final entry in entries)
                  CupertinoActionSheetAction(
                    isDestructiveAction: entry.destructive,
                    onPressed: () => Navigator.pop(context, entry.value),
                    child: Text(entry.label),
                  ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context),
                child: Text(T('i18n.cancel')),
              ),
            ),
          );
    if (!mounted) return;
    if (action == 'pin') {
      await _run(() async {
        await ChatStore.instance.pinTopic(topic.id, topic.pinnedAt == 0);
        await _load();
        widget.onChanged();
      });
    }
    if (action == 'move') await _run(() => _move(topic));
    if (action == 'rename') await _rename(topic);
    if (action == 'delete') await _delete(topic);
  }

  Future<void> _rename(ChatTopic topic) async {
    final controller = TextEditingController(text: topic.title);
    final title = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.rename_chat')),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            placeholder: T('i18n.chat_title'),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(T('i18n.cancel')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(T('i18n.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await ChatStore.instance.updateTopic(topic.id, title: title);
    await _load();
    widget.onChanged();
  }

  Future<void> _delete(ChatTopic topic) async {
    if (topic.id == widget.generatingTopicId ||
        AgentRunner.active?.currentTask?.topicId == topic.id) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(T('i18n.stop_the_response_first')),
          content: Text(T('i18n.stop_before_delete_chat')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(T('i18n.ok')),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.delete_this_chat')),
        content: Text(T('i18n.its_local_messages_will')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(T('i18n.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(T('i18n.delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChatStore.instance.deleteTopic(topic.id);
    await _load();
    widget.onChanged();
  }

  Widget _filterHeader() => Semantics(
    header: true,
    child: CupertinoButton(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      minimumSize: const Size(0, 44),
      onPressed: _chooseProject,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _selection.id == null
                  ? T(
                      _selection.ungrouped
                          ? 'i18n.ungrouped_chats'
                          : 'i18n.all_chats',
                    )
                  : _projects
                            .where((p) => p.id == _selection.id)
                            .firstOrNull
                            ?.name ??
                        '',
              style: TextStyle(
                color: IosColors.label,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 7),
          Icon(
            CupertinoIcons.chevron_down,
            size: 13,
            color: IosColors.secondary,
          ),
        ],
      ),
    ),
  );

  Widget _emptyList() {
    final searching = _search.text.trim().isNotEmpty;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 21, 16, 0),
            child: _filterHeader(),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: const Alignment(0, -.25),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    searching
                        ? CupertinoIcons.search
                        : CupertinoIcons.chat_bubble_2,
                    size: 32,
                    color: IosColors.secondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    T(
                      searching
                          ? 'i18n.no_search_results'
                          : 'i18n.no_chats_yet',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: IosColors.secondary, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: IosColors.background,
    child: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: isDesktopApp ? desktopToolbarHeight : 56,
            child: Row(
              children: [
                if (!widget.persistent)
                  IosNavButton(
                    icon: CupertinoIcons.xmark,
                    onPressed: widget.onClose,
                  )
                else
                  const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    T(widget.persistent ? 'AI Link' : 'i18n.chats'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: IosColors.label,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IosNavButton(
                  icon: CupertinoIcons.square_pencil,
                  onPressed: () => widget.onNewInProject != null
                      ? widget.onNewInProject!(_selection.id)
                      : widget.onNew(),
                ),
              ],
            ),
          ),
          Divider(height: .5, color: IosColors.separator),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: CupertinoSearchTextField(
              controller: _search,
              placeholder: T('i18n.search_history'),
              onChanged: (_) {
                _searchRevision++;
                _debounce?.cancel();
                setState(() => _searching = _search.text.trim().isNotEmpty);
                _debounce = Timer(
                  const Duration(milliseconds: 250),
                  _searchHistory,
                );
              },
            ),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: IosColors.destructive)),
          Expanded(
            child:
                (_search.text.trim().isEmpty
                    ? _visibleTopics.isEmpty
                    : !_searching && _matches.isEmpty)
                ? _emptyList()
                : ListView(
                    children: [
                      if (_search.text.trim().isNotEmpty) ...[
                        if (_searching)
                          IosSection(
                            header: _filterHeader(),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(20),
                                child: CupertinoActivityIndicator(),
                              ),
                            ],
                          )
                        else
                          IosSection(
                            header: _filterHeader(),
                            footer: T('i18n.history_matches_detail'),
                            children: [
                              for (final match in _matches)
                                IosRow(
                                  title: match.topic.title,
                                  subtitle: match.excerpt,
                                  leading: _topicIcon(match.topic),
                                  onTap: () {
                                    if (widget.onSearchSelect != null) {
                                      widget.onSearchSelect!(
                                        match.topic.id,
                                        match.messageId,
                                      );
                                    } else {
                                      widget.onSelect(match.topic.id);
                                    }
                                  },
                                ),
                            ],
                          ),
                      ] else
                        IosSection(
                          header: _filterHeader(),
                          children: [
                            for (final topic in _visibleTopics)
                              IosRow(
                                title: topic.title,
                                subtitle:
                                    '${topic.pinnedAt > 0 ? '${T('i18n.pinned_chat')} · ' : ''}${_projects.where((p) => p.id == topic.projectId).firstOrNull?.name ?? ''}${topic.projectId != null ? ' · ' : ''}${_providers.where((p) => p.id == topic.providerId).firstOrNull?.name ?? T('i18n.service_deleted')} · ${topic.model}',
                                leading: _topicIcon(topic),
                                trailing: Builder(
                                  builder: (anchorContext) => CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    minimumSize: const Size(38, 38),
                                    onPressed: () =>
                                        _actions(topic, anchorContext),
                                    child: Icon(
                                      CupertinoIcons.ellipsis,
                                      color: IosColors.secondary,
                                      size: 21,
                                    ),
                                  ),
                                ),
                                chevron: false,
                                onTap: () => widget.onSelect(topic.id),
                              ),
                          ],
                        ),
                    ],
                  ),
          ),
          Divider(height: .5, color: IosColors.separator),
          SizedBox(
            height: 62,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: CupertinoButton(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 4),
                onPressed: widget.onSettings,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.gear, color: IosColors.blue, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      T('i18n.settings'),
                      style: TextStyle(color: IosColors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
