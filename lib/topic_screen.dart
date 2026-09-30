import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_preferences.dart';

import 'data.dart';
import 'ios_style.dart';

class TopicScreen extends StatefulWidget {
  const TopicScreen({
    super.key,
    this.selectedId,
    this.generatingTopicId,
    required this.onClose,
    required this.onSelect,
    required this.onNew,
    required this.onSettings,
    required this.onChanged,
  });

  final int? selectedId;
  final int? generatingTopicId;
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
  List<ProviderConfig> _providers = [];
  Set<int> _watchTopicIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final topics = await ChatStore.instance.topics();
    final providers = await ChatStore.instance.providers();
    final watchTopicIds = await ChatStore.instance.watchTopicIds();
    if (mounted) {
      setState(() {
        _topics = topics;
        _providers = providers;
        _watchTopicIds = watchTopicIds;
      });
    }
  }

  Future<void> _actions(ChatTopic topic) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(topic.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'rename'),
            child: Text(tr('重命名')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: Text(tr('删除话题')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _rename(topic);
    if (action == 'delete') await _delete(topic);
  }

  Future<void> _rename(ChatTopic topic) async {
    final controller = TextEditingController(text: topic.title);
    final title = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('重命名话题')),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            placeholder: tr('话题名称'),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr('保存')),
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
    if (topic.id == widget.generatingTopicId) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(tr('请先停止生成')),
          content: Text(tr('停止当前回复后即可删除这个话题。')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('好')),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('删除这个话题？')),
        content: Text(tr('本地聊天记录会一并删除，无法恢复。')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('取消')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChatStore.instance.deleteTopic(topic.id);
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: IosColors.background,
    child: SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                IosNavButton(
                  icon: CupertinoIcons.xmark,
                  onPressed: widget.onClose,
                ),
                Expanded(
                  child: Text(
                    tr('对话列表'),
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
                  onPressed: widget.onNew,
                ),
              ],
            ),
          ),
          Divider(height: .5, color: IosColors.separator),
          Expanded(
            child: ListView(
              children: [
                if (_topics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 90, 20, 0),
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.chat_bubble_2,
                          size: 42,
                          color: IosColors.secondary,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          tr('还没有对话'),
                          style: TextStyle(color: IosColors.secondary),
                        ),
                      ],
                    ),
                  )
                else
                  IosSection(
                    title: '最近',
                    children: [
                      for (final topic in _topics)
                        IosRow(
                          title: topic.title,
                          subtitle:
                              '${_providers.where((p) => p.id == topic.providerId).firstOrNull?.name ?? '服务已删除'} · ${topic.model}',
                          leading: Icon(
                            _watchTopicIds.contains(topic.id)
                                ? Icons.watch_outlined
                                : CupertinoIcons.chat_bubble_text,
                            color: topic.id == widget.selectedId
                                ? IosColors.blue
                                : IosColors.secondary,
                            size: 22,
                          ),
                          trailing: CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(38, 38),
                            onPressed: () => _actions(topic),
                            child: Icon(
                              CupertinoIcons.ellipsis,
                              color: IosColors.secondary,
                              size: 21,
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
                    Text(tr('设置'), style: TextStyle(color: IosColors.blue)),
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
