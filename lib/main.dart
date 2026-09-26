import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'data.dart';
import 'provider_screen.dart';

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
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: brand, surface: canvas),
      appBarTheme: const AppBarTheme(
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE4E1E6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brand, width: 1.5),
        ),
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
      MaterialPageRoute(builder: (_) => const ProviderScreen()),
    );
    await _load();
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

  Future<void> _renameTopic(ChatTopic topic) async {
    final controller = TextEditingController(text: topic.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名话题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: '话题名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
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

  Future<void> _deleteTopic(ChatTopic topic) async {
    if (_sending && _sendingTopicId == topic.id) {
      _notify('请先停止生成，再删除话题');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个话题？'),
        content: const Text('本地聊天记录会一并删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_topic?.id == topic.id && _sending) _stopReply();
    await ChatStore.instance.deleteTopic(topic.id);
    if (_topic?.id == topic.id) _topic = null;
    await _load();
  }

  Future<void> _changeModel() async {
    final topic = _topic;
    if (topic == null || _providers.isEmpty) return;
    var selectedId = topic.providerId ?? _providers.first.id;
    final controller = TextEditingController(text: topic.model);
    final choice = await showDialog<({int id, String model})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('切换服务与模型'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _providers.any((p) => p.id == selectedId)
                    ? selectedId
                    : _providers.first.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '服务'),
                items: _providers
                    .map(
                      (provider) => DropdownMenuItem(
                        value: provider.id,
                        child: Text(provider.name),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  update(() => selectedId = id);
                  controller.text = _providers
                      .firstWhere((p) => p.id == id)
                      .model;
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: '模型 ID'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final model = controller.text.trim();
                if (model.isNotEmpty) {
                  Navigator.pop(context, (id: selectedId, model: model));
                }
              },
              child: const Text('切换'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (choice == null) return;
    await ChatStore.instance.updateTopic(
      topic.id,
      providerId: choice.id,
      model: choice.model,
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

  void _notify(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final provider = _providers
        .where((p) => p.id == _topic?.providerId)
        .firstOrNull;
    return Scaffold(
      drawer: _drawer(),
      appBar: AppBar(
        backgroundColor: canvas,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: '话题列表',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('模型之间'),
        actions: [
          IconButton(
            tooltip: '新对话',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newTopic,
          ),
          IconButton(
            tooltip: '模型服务',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openProviders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                      color: const Color(0xFFFFF1EE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFF9C3D32)),
                    ),
                  ),
                _composer(),
              ],
            ),
    );
  }

  Widget _modelBar(ProviderConfig? provider) => InkWell(
    onTap: _changeModel,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE9E7E9))),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF52B899),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              provider?.name ?? '服务已删除',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _topic!.model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const Icon(Icons.expand_more, size: 18, color: Colors.grey),
        ],
      ),
    ),
  );

  Widget _welcome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF887CFA), brand],
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: brand.withValues(alpha: .22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '一个地方，和不同模型对话',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '接入自己的 API，创建话题，随时继续上次的讨论。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF78798A),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _providers.isEmpty ? _openProviders : _newTopic,
            style: FilledButton.styleFrom(
              backgroundColor: brand,
              minimumSize: const Size(190, 52),
            ),
            icon: const Icon(Icons.add),
            label: Text(_providers.isEmpty ? '接入模型服务' : '开始新对话'),
          ),
          const SizedBox(height: 20),
          Text(
            _providers.isEmpty
                ? '支持 OpenAI、Claude、DeepSeek、GLM、千问等'
                : '已接入 ${_providers.length} 个服务 · 记录保存在本机',
            style: const TextStyle(color: Color(0xFF9999A6), fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _chatList() {
    final showReply = _sending && _sendingTopicId == _topic?.id;
    final count = _messages.length + (showReply ? 1 : 0);
    if (count == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 42,
              color: brand.withValues(alpha: .6),
            ),
            const SizedBox(height: 14),
            const Text(
              '新话题已经准备好',
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '输入第一条消息，开始讨论。',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!user) ...[
            const CircleAvatar(
              radius: 15,
              backgroundColor: brand,
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .8,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: user ? const Color(0xFF34344F) : Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: user
                    ? null
                    : Border.all(color: const Color(0xFFEAE8E7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isEmpty && loading)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    SelectableText(
                      content,
                      style: TextStyle(
                        color: user ? Colors.white : ink,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  if (loading && content.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 12,
                        width: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (!loading && !user)
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: '复制',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: content));
                          if (mounted) _notify('已复制');
                        },
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
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE9E7E9))),
    ),
    padding: const EdgeInsets.fromLTRB(16, 11, 16, 10),
    child: SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _providers.isEmpty ? '先接入模型服务…' : '输入消息…',
                filled: true,
                fillColor: canvas,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          IconButton.filled(
            tooltip: _sending ? '停止生成' : '发送',
            icon: Icon(
              _sending ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            ),
            onPressed: _sending ? _stopReply : (_starting ? null : _send),
            style: IconButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              minimumSize: const Size(46, 46),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _drawer() => Drawer(
    backgroundColor: canvas,
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: brand,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '模型之间',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _newTopic();
              },
              style: FilledButton.styleFrom(
                backgroundColor: brand,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.add),
              label: const Text('新对话'),
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '话题',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8E8D99),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _topics.isEmpty
                ? const Center(
                    child: Text('暂无话题', style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: _topics.length,
                    itemBuilder: (context, index) {
                      final topic = _topics[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        child: ListTile(
                          selected: topic.id == _topic?.id,
                          selectedTileColor: brand.withValues(alpha: .1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          leading: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                          ),
                          title: Text(
                            topic.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _selectTopic(topic.id);
                          },
                          trailing: PopupMenuButton<String>(
                            tooltip: '话题操作',
                            onSelected: (value) => value == 'rename'
                                ? _renameTopic(topic)
                                : _deleteTopic(topic),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('重命名'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('模型服务'),
            onTap: () {
              Navigator.pop(context);
              _openProviders();
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Text(
              '聊天记录保存在本机 · 发送时会传给所选服务',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    ),
  );
}
