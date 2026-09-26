import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'assistant_markdown.dart';
import 'data.dart';
import 'ios_style.dart';
import 'provider_screen.dart';
import 'topic_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ModelChatApp());
}

class ModelChatApp extends StatelessWidget {
  const ModelChatApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '模型之间',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => CupertinoTheme(
      data: const CupertinoThemeData(
        primaryColor: IosColors.blue,
        brightness: Brightness.light,
      ),
      child: child ?? const SizedBox.shrink(),
    ),
    theme: ThemeData(
      useMaterial3: false,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: IosColors.background,
      primaryColor: IosColors.blue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: IosColors.blue,
        surface: IosColors.surface,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    ),
    home: const ChatHome(),
  );
}

class ChatHome extends StatefulWidget {
  const ChatHome({super.key});
  @override
  State<ChatHome> createState() => _ChatHomeState();
}

class _ChatHomeState extends State<ChatHome> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ProviderConfig> _providers = [];
  List<ChatTopic> _topics = [];
  List<ChatMessage> _messages = [];
  ChatTopic? _topic;
  ModelApiClient? _activeClient;
  String _reply = '';
  String? _error;
  bool _loading = true;
  bool _starting = false;
  bool _sending = false;
  bool _cancelRequested = false;
  int? _sendingTopicId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _activeClient?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final providers = await ChatStore.instance.providers();
      final topics = await ChatStore.instance.topics();
      final selected = _topic == null
          ? null
          : topics.where((item) => item.id == _topic!.id).firstOrNull;
      final messages = selected == null
          ? <ChatMessage>[]
          : await ChatStore.instance.messages(selected.id);
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _topics = topics;
        _topic = selected;
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开本地数据：$error';
        });
      }
    }
  }

  Future<void> _openProviders() async {
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(builder: (_) => const ProviderScreen()),
    );
    await _load();
  }

  Future<void> _openTopics() async {
    final choice = await Navigator.push<int>(
      context,
      CupertinoPageRoute(
        builder: (_) => TopicScreen(
          selectedId: _topic?.id,
          generatingTopicId: _sendingTopicId,
        ),
      ),
    );
    await _load();
    if (!mounted || choice == null) return;
    if (choice == 0) {
      await _newTopic();
    } else if (choice == -1) {
      await _openProviders();
    } else {
      await _selectTopic(choice);
    }
  }

  Future<void> _newTopic() async {
    if (_providers.isEmpty) {
      await _openProviders();
      if (_providers.isEmpty) return;
    }
    final id = await ChatStore.instance.createTopic(_providers.first);
    await _load();
    await _selectTopic(id);
  }

  Future<void> _selectTopic(int id) async {
    final topic = _topics.where((item) => item.id == id).firstOrNull;
    if (topic == null) return;
    final messages = await ChatStore.instance.messages(id);
    if (!mounted) return;
    setState(() {
      _topic = topic;
      _messages = messages;
      _error = null;
      _reply = '';
    });
    _scrollToBottom();
  }

  Future<void> _changeModel() async {
    final topic = _topic;
    if (topic == null || _providers.isEmpty) return;
    final selectedId = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择模型服务'),
        actions: [
          for (final provider in _providers)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, provider.id),
              child: Text(provider.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (selectedId == null || !mounted) return;
    final provider = _providers.firstWhere((item) => item.id == selectedId);
    final controller = TextEditingController(
      text: selectedId == topic.providerId ? topic.model : provider.model,
    );
    final model = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('模型 ID'),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: '输入模型 ID',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (model == null || model.isEmpty) return;
    await ChatStore.instance.updateTopic(
      topic.id,
      providerId: selectedId,
      model: model,
    );
    await _load();
  }

  void _stopReply() {
    _cancelRequested = true;
    _activeClient?.cancel();
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty || _starting || _sending) return;
    setState(() => _starting = true);
    try {
      await _sendMessage(content);
    } catch (error) {
      if (mounted) setState(() => _error = '发送失败：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _sendMessage(String content) async {
    if (_providers.isEmpty) {
      await _openProviders();
      if (_providers.isEmpty) return;
    }
    if (_topic == null) await _newTopic();
    final topic = _topic;
    if (topic == null) return;
    final provider = _providers
        .where((p) => p.id == topic.providerId)
        .firstOrNull;
    if (provider == null) {
      _notify('此话题原来的服务已删除，请切换服务与模型');
      return;
    }
    final key = await ChatStore.instance.apiKey(provider.id);
    if (key == null || key.isEmpty) {
      _notify('找不到密钥，请重新编辑服务配置');
      return;
    }
    _input.clear();
    final first = _messages.isEmpty;
    await ChatStore.instance.addMessage(topic.id, 'user', content);
    if (first) {
      final title = content.replaceAll(RegExp(r'\s+'), ' ');
      await ChatStore.instance.updateTopic(
        topic.id,
        title: title.length > 28 ? '${title.substring(0, 28)}…' : title,
      );
    }
    final history = await ChatStore.instance.messages(topic.id);
    if (!mounted) return;
    setState(() {
      _messages = history;
      _sending = true;
      _sendingTopicId = topic.id;
      _reply = '';
      _error = null;
      _cancelRequested = false;
    });
    _scrollToBottom();
    await _refreshTopics();
    final client = ModelApiClient(provider, key);
    _activeClient = client;
    var answer = '';
    try {
      await for (final chunk in client.streamReply(history, topic.model)) {
        answer += chunk;
        if (mounted && _topic?.id == topic.id) {
          setState(() => _reply = answer);
          _scrollToBottom();
        }
      }
    } catch (error) {
      if (!_cancelRequested && mounted && _topic?.id == topic.id) {
        setState(() => _error = error.toString());
      }
    } finally {
      _activeClient = null;
      if (answer.isNotEmpty) {
        await ChatStore.instance.addMessage(topic.id, 'assistant', answer);
      }
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingTopicId = null;
          _reply = '';
        });
        if (_topic?.id == topic.id) {
          final messages = await ChatStore.instance.messages(topic.id);
          if (mounted) setState(() => _messages = messages);
          _scrollToBottom();
        }
        await _refreshTopics();
      }
    }
  }

  Future<void> _refreshTopics() async {
    final topics = await ChatStore.instance.topics();
    if (!mounted) return;
    setState(() {
      _topics = topics;
      if (_topic != null) {
        _topic = topics.where((item) => item.id == _topic!.id).firstOrNull;
      }
    });
  }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  });

  void _notify(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, textAlign: TextAlign.center),
      behavior: SnackBarBehavior.floating,
      backgroundColor: IosColors.label,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ),
  );

  Future<void> _openMarkdownLink(String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      _notify('无法打开这个链接');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        _notify('无法打开这个链接');
      }
    } catch (_) {
      if (mounted) _notify('无法打开这个链接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _providers
        .where((item) => item.id == _topic?.providerId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: '模型之间',
        leading: IosNavButton(
          icon: CupertinoIcons.chat_bubble_2,
          label: '对话',
          onPressed: _openTopics,
        ),
        actions: [
          IosNavButton(
            icon: CupertinoIcons.square_pencil,
            onPressed: _newTopic,
          ),
          IosNavButton(
            icon: CupertinoIcons.slider_horizontal_3,
            onPressed: _openProviders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : Column(
              children: [
                if (_topic != null) _modelBar(provider),
                Expanded(child: _topic == null ? _welcome() : _chatList()),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9E8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: IosColors.destructive,
                        fontSize: 13,
                      ),
                    ),
                  ),
                _composer(),
              ],
            ),
    );
  }

  Widget _modelBar(ProviderConfig? provider) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _changeModel,
    child: Container(
      color: IosColors.surface,
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
      child: Row(
        children: [
          Container(
            width: 33,
            height: 33,
            decoration: BoxDecoration(
              color: IosColors.blue.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              CupertinoIcons.chat_bubble_2,
              color: IosColors.blue,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider?.name ?? '服务已删除',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: IosColors.label,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _topic!.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: IosColors.secondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_down,
            size: 16,
            color: IosColors.secondary,
          ),
        ],
      ),
    ),
  );

  Widget _welcome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: IosColors.blue.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              CupertinoIcons.chat_bubble_2_fill,
              color: IosColors.blue,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '模型之间',
            style: TextStyle(
              color: IosColors.label,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            '一个地方，和不同模型继续对话。',
            textAlign: TextAlign.center,
            style: TextStyle(color: IosColors.secondary, fontSize: 15),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 225,
            child: IosPrimaryButton(
              label: _providers.isEmpty ? '接入模型服务' : '开始新对话',
              onPressed: _providers.isEmpty ? _openProviders : _newTopic,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chatList() {
    final showReply = _sending && _sendingTopicId == _topic?.id;
    final count = _messages.length + (showReply ? 1 : 0);
    if (count == 0) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.chat_bubble_text,
              size: 40,
              color: IosColors.secondary,
            ),
            SizedBox(height: 13),
            Text(
              '开始新的对话',
              style: TextStyle(
                color: IosColors.label,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '输入消息，开始讨论。',
              style: TextStyle(color: IosColors.secondary, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return _bubble('assistant', _reply, loading: true);
        }
        final message = _messages[index];
        return _bubble(message.role, message.content);
      },
    );
  }

  Widget _bubble(String role, String content, {bool loading = false}) {
    final user = role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .86,
              ),
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
              decoration: BoxDecoration(
                color: user ? IosColors.blue : IosColors.assistant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(user ? 18 : 5),
                  bottomRight: Radius.circular(user ? 5 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isEmpty && loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: CupertinoActivityIndicator(radius: 10),
                    )
                  else if (user)
                    SelectableText(
                      content,
                      style: const TextStyle(
                        color: IosColors.surface,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    )
                  else
                    AssistantMarkdown(
                      data: content,
                      onTapLink: _openMarkdownLink,
                    ),
                  if (loading && content.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: CupertinoActivityIndicator(radius: 7),
                    ),
                  if (!loading && !user)
                    Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 30),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: content));
                          if (mounted) _notify('已复制');
                        },
                        child: const Icon(
                          CupertinoIcons.doc_on_doc,
                          size: 17,
                          color: IosColors.secondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() => Container(
    decoration: const BoxDecoration(
      color: IosColors.surface,
      border: Border(top: BorderSide(color: IosColors.separator, width: .5)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 9, 12, 4),
    child: SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              placeholder: _providers.isEmpty ? '先接入模型服务' : '发送消息',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: IosColors.surface,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: const Color(0xFFD1D1D6)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 40),
            onPressed: _sending ? _stopReply : (_starting ? null : _send),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _starting ? IosColors.secondary : IosColors.blue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _sending ? CupertinoIcons.stop_fill : CupertinoIcons.arrow_up,
                color: IosColors.surface,
                size: 21,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
