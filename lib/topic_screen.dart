import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'ios_style.dart';

class TopicScreen extends StatefulWidget {
  const TopicScreen({super.key, this.selectedId, this.generatingTopicId});

  final int? selectedId;
  final int? generatingTopicId;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  List<ChatTopic> _topics = [];
  List<ProviderConfig> _providers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final topics = await ChatStore.instance.topics();
    final providers = await ChatStore.instance.providers();
    if (mounted) {
      setState(() {
        _topics = topics;
        _providers = providers;
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
            child: const Text('重命名'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('删除话题'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
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
        title: const Text('重命名话题'),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            placeholder: '话题名称',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await ChatStore.instance.updateTopic(topic.id, title: title);
    await _load();
  }

  Future<void> _delete(ChatTopic topic) async {
    if (topic.id == widget.generatingTopicId) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('请先停止生成'),
          content: const Text('停止当前回复后即可删除这个话题。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除这个话题？'),
        content: const Text('本地聊天记录会一并删除，无法恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ChatStore.instance.deleteTopic(topic.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: '对话',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IosNavButton(
          icon: CupertinoIcons.square_pencil,
          onPressed: () => Navigator.pop(context, 0),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        children: [
          if (_topics.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(30, 100, 30, 0),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.chat_bubble_2,
                    size: 48,
                    color: IosColors.secondary,
                  ),
                  SizedBox(height: 14),
                  Text('还没有对话', style: TextStyle(fontSize: 17)),
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
                      CupertinoIcons.chat_bubble_text,
                      color: topic.id == widget.selectedId
                          ? IosColors.blue
                          : IosColors.secondary,
                      size: 22,
                    ),
                    trailing: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(38, 38),
                      onPressed: () => _actions(topic),
                      child: const Icon(
                        CupertinoIcons.ellipsis,
                        color: IosColors.secondary,
                        size: 21,
                      ),
                    ),
                    chevron: false,
                    onTap: () => Navigator.pop(context, topic.id),
                  ),
              ],
            ),
          IosSection(
            title: '设置',
            children: [
              IosRow(
                title: '模型服务',
                leading: const Icon(
                  CupertinoIcons.slider_horizontal_3,
                  color: IosColors.blue,
                  size: 22,
                ),
                onTap: () => Navigator.pop(context, -1),
              ),
            ],
          ),
          const SizedBox(height: 26),
        ],
      ),
    ),
  );
}
