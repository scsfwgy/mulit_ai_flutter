import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'app_preferences.dart';
import 'assistant_markdown.dart';
import 'chat_more_menu.dart';
import 'chat_model_selector.dart';
import 'chat_model_title.dart';
import 'data.dart';
import 'ios_style.dart';
import 'provider_screen.dart';
import 'settings_screen.dart';
import 'topic_screen.dart';

enum _ChatErrorAction { none, configure, model, request, retry }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppPreferences.instance.load();
  } catch (_) {
    // ChatHome reports storage errors; keep the app open with default appearance.
  }
  runApp(const ModelChatApp());
}

class ModelChatApp extends StatelessWidget {
  const ModelChatApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (context, _) => MaterialApp(
      title: tr('模型之间'),
      debugShowCheckedModeBanner: false,
      locale: AppPreferences.instance.locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: AppPreferences.instance.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarColor: IosColors.background,
          systemNavigationBarIconBrightness: AppPreferences.instance.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: CupertinoTheme(
          data: CupertinoThemeData(
            primaryColor: IosColors.blue,
            brightness: AppPreferences.instance.dark
                ? Brightness.dark
                : Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
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
      darkTheme: ThemeData(
        useMaterial3: false,
        platform: TargetPlatform.iOS,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: IosColors.background,
        primaryColor: IosColors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: IosColors.blue,
          brightness: Brightness.dark,
          surface: IosColors.surface,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      themeMode: AppPreferences.instance.themeMode,
      home: const ChatHome(),
    ),
  );
}

class ChatHome extends StatefulWidget {
  const ChatHome({super.key});
  @override
  State<ChatHome> createState() => _ChatHomeState();
}

class _ChatHomeState extends State<ChatHome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ProviderConfig> _providers = [];
  List<ChatTopic> _topics = [];
  List<ChatMessage> _messages = [];
  ChatTopic? _topic;
  int? _draftProviderId;
  String? _draftModel;
  ModelApiClient? _activeClient;
  final _titleClients = <ModelApiClient>{};
  String _reply = '';
  String? _error;
  _ChatErrorAction _errorAction = _ChatErrorAction.none;
  bool _loading = true;
  bool _starting = false;
  bool _sending = false;
  bool _cancelRequested = false;
  int? _sendingTopicId;

  int? get _currentProviderId => _topic?.providerId ?? _draftProviderId;
  String? get _currentModel => _topic?.model ?? _draftModel;
  bool get _hasDraft => _draftProviderId != null && _draftModel != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _activeClient?.cancel();
    for (final client in _titleClients) {
      client.cancel();
    }
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
        if (_draftProviderId != null &&
            !providers.any((item) => item.id == _draftProviderId)) {
          _draftProviderId = providers.firstOrNull?.id;
          _draftModel = providers.firstOrNull?.model;
        }
        _messages = messages;
        _loading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开本地数据：$error';
          _errorAction = _ChatErrorAction.none;
        });
      }
    }
  }

  Future<void> _openProviders() async {
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => ProviderScreen(canClearData: _canClearData),
      ),
    );
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      CupertinoPageRoute(
        builder: (_) => SettingsScreen(canClearData: _canClearData),
      ),
    );
    await _load();
  }

  void _openTopics() => _scaffoldKey.currentState?.openDrawer();

  bool _canClearData() => !_sending && !_starting && _titleClients.isEmpty;

  void _closeTopics() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _chooseTopic(int id) async {
    _closeTopics();
    await _selectTopic(id);
  }

  Future<void> _newFromDrawer() async {
    _closeTopics();
    await _newTopic();
  }

  Future<void> _settingsFromDrawer() async {
    _closeTopics();
    await _openSettings();
  }

  Future<void> _newTopic() async {
    if (_providers.isEmpty) {
      await _openProviders();
      if (!mounted || _providers.isEmpty) return;
    }
    final previous = _providers
        .where((item) => item.id == _currentProviderId)
        .firstOrNull;
    final provider = previous ?? _providers.first;
    final model = previous == null
        ? provider.model
        : _currentModel ?? provider.model;
    setState(() {
      _topic = null;
      _draftProviderId = provider.id;
      _draftModel = model;
      _messages = [];
      _reply = '';
      _error = null;
      _errorAction = _ChatErrorAction.none;
    });
  }

  Future<void> _selectTopic(int id) async {
    final topic = _topics.where((item) => item.id == id).firstOrNull;
    if (topic == null) return;
    final messages = await ChatStore.instance.messages(id);
    if (!mounted) return;
    setState(() {
      _topic = topic;
      _draftProviderId = null;
      _draftModel = null;
      _messages = messages;
      _error = null;
      _errorAction = _ChatErrorAction.none;
      _reply = '';
    });
    _scrollToBottom();
  }

  Future<void> _changeModel() async {
    final topic = _topic;
    if (_providers.isEmpty) return;
    if (_sending || _starting) {
      _notify(tr('请先停止当前回复，再切换模型'));
      return;
    }
    final selection = await Navigator.push<ChatModelSelection>(
      context,
      CupertinoPageRoute(
        builder: (_) => ChatModelSelector(
          providers: _providers,
          topics: _topics,
          providerId: _currentProviderId,
          model: _currentModel,
          loadModels: _loadModels,
          loadCachedModels: ChatStore.instance.cachedModels,
        ),
      ),
    );
    if (selection == null || !mounted || _topic?.id != topic?.id) return;
    if (topic == null) {
      setState(() {
        _draftProviderId = selection.providerId;
        _draftModel = selection.model;
        _error = null;
        _errorAction = _ChatErrorAction.none;
      });
    } else {
      await ChatStore.instance.updateTopic(
        topic.id,
        providerId: selection.providerId,
        model: selection.model,
      );
      await _load();
      if (mounted) {
        setState(() {
          _error = null;
          _errorAction = _ChatErrorAction.none;
        });
      }
    }
  }

  Future<List<String>> _loadModels(ProviderConfig provider) async {
    final key = await ChatStore.instance.apiKey(provider.id);
    if (key == null || key.isEmpty) {
      throw const ApiException('请先在服务设置中填写 API Key');
    }
    final models = await ModelApiClient(provider, key).fetchModels();
    if (models.isNotEmpty) {
      try {
        await ChatStore.instance.saveModelCache(provider, models);
      } catch (_) {
        // A cache write must not hide a usable model list returned by the API.
      }
    }
    return models;
  }

  Future<void> _editCurrentProvider() async {
    final provider = _providers
        .where((item) => item.id == _currentProviderId)
        .firstOrNull;
    if (provider == null) {
      await _openProviders();
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(builder: (_) => ProviderEditor(config: provider)),
    );
    await _load();
    if (changed == true && mounted) {
      setState(() {
        _error = null;
        _errorAction = _ChatErrorAction.none;
      });
    }
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
      if (mounted) {
        setState(() {
          _error = '发送失败：$error';
          _errorAction = _ChatErrorAction.none;
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _sendMessage(String content) async {
    if (_providers.isEmpty) {
      await _openProviders();
      if (!mounted || _providers.isEmpty) return;
    }
    final initialTopicId = _topic?.id;
    final providerId = _currentProviderId ?? _providers.first.id;
    final provider = _providers.where((p) => p.id == providerId).firstOrNull;
    if (provider == null) {
      setState(() {
        _error = '此话题原来的服务已删除，请重新选择模型。';
        _errorAction = _ChatErrorAction.model;
      });
      return;
    }
    final model = _currentModel ?? provider.model;
    final key = await ChatStore.instance.apiKey(provider.id);
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      setState(() {
        _error = '此服务尚未配置 API Key。';
        _errorAction = _ChatErrorAction.configure;
      });
      return;
    }
    final systemPrompt = await ChatStore.instance.systemPrompt(
      provider.id,
      model,
    );
    if (!mounted ||
        _topic?.id != initialTopicId ||
        (_currentProviderId != null && _currentProviderId != providerId) ||
        (_currentModel != null && _currentModel != model)) {
      return;
    }
    ChatTopic topic;
    if (_topic == null) {
      final id = await ChatStore.instance.createTopicWithMessage(
        provider,
        model,
        content,
      );
      final topics = await ChatStore.instance.topics();
      topic = topics.firstWhere((item) => item.id == id);
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _topic = topic;
        _draftProviderId = null;
        _draftModel = null;
      });
    } else {
      topic = _topic!;
      final first = _messages.isEmpty;
      await ChatStore.instance.addMessage(topic.id, 'user', content);
      if (first) {
        await ChatStore.instance.updateTopic(
          topic.id,
          title: initialTopicTitle(content),
        );
      }
    }
    _input.clear();
    final history = await ChatStore.instance.messages(topic.id);
    await _requestReply(topic, provider, key, systemPrompt, history);
  }

  Future<void> _retryReply() async {
    final topic = _topic;
    if (topic == null || _starting || _sending) return;
    setState(() => _starting = true);
    try {
      final history = await ChatStore.instance.messages(topic.id);
      if (history.isEmpty || history.last.role != 'user') return;
      final provider = _providers
          .where((item) => item.id == topic.providerId)
          .firstOrNull;
      if (provider == null) {
        setState(() {
          _error = '服务配置已删除，请重新选择模型。';
          _errorAction = _ChatErrorAction.model;
        });
        return;
      }
      final key = await ChatStore.instance.apiKey(provider.id);
      if (!mounted) return;
      if (key == null || key.isEmpty) {
        setState(() {
          _error = '此服务尚未配置 API Key。';
          _errorAction = _ChatErrorAction.configure;
        });
        return;
      }
      final systemPrompt = await ChatStore.instance.systemPrompt(
        provider.id,
        topic.model,
      );
      if (!mounted || _topic?.id != topic.id) return;
      await _requestReply(topic, provider, key, systemPrompt, history);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '重试失败：$error';
          _errorAction = _ChatErrorAction.none;
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _requestReply(
    ChatTopic topic,
    ProviderConfig provider,
    String key,
    String systemPrompt,
    List<ChatMessage> history,
  ) async {
    if (!mounted) return;
    setState(() {
      _messages = history;
      _sending = true;
      _sendingTopicId = topic.id;
      _reply = '';
      _error = null;
      _errorAction = _ChatErrorAction.none;
      _cancelRequested = false;
    });
    _scrollToBottom();
    await _refreshTopics();
    final client = ModelApiClient(provider, key);
    _activeClient = client;
    var answer = '';
    var completed = false;
    try {
      await for (final chunk in client.streamReply(
        history,
        topic.model,
        systemPrompt: systemPrompt,
      )) {
        answer += chunk;
        if (mounted && _topic?.id == topic.id) {
          setState(() => _reply = answer);
          _scrollToBottom();
        }
      }
      completed = !_cancelRequested;
    } catch (error) {
      if (!_cancelRequested && mounted && _topic?.id == topic.id) {
        setState(() {
          _error = error.toString();
          _errorAction = error is ApiException
              ? switch (error.kind) {
                  ApiErrorKind.network when answer.isEmpty =>
                    _ChatErrorAction.retry,
                  ApiErrorKind.auth => _ChatErrorAction.configure,
                  ApiErrorKind.model => _ChatErrorAction.model,
                  _ => _ChatErrorAction.request,
                }
              : _ChatErrorAction.request;
        });
      }
    } finally {
      _activeClient = null;
      if (answer.isNotEmpty) {
        await ChatStore.instance.addMessage(topic.id, 'assistant', answer);
      }
      final shouldGenerateTitle =
          completed &&
          answer.isNotEmpty &&
          history.length == 1 &&
          history.first.role == 'user';
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
      if (shouldGenerateTitle && mounted) {
        unawaited(
          _generateTitle(topic, provider, key, history.first.content, answer),
        );
      }
    }
  }

  Future<void> _generateTitle(
    ChatTopic topic,
    ProviderConfig provider,
    String key,
    String firstMessage,
    String answer,
  ) async {
    final client = ModelApiClient(provider, key);
    _titleClients.add(client);
    try {
      final title = await client
          .generateTopicTitle(topic.model, firstMessage, answer)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              client.cancel();
              return null;
            },
          );
      if (title == null) return;
      final changed = await ChatStore.instance.updateTopicTitleIfUnchanged(
        topic.id,
        initialTopicTitle(firstMessage),
        title,
      );
      if (changed && mounted) await _refreshTopics();
    } catch (_) {
      // The first-message title remains available if summarization fails.
    } finally {
      _titleClients.remove(client);
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
      content: Text(tr(message), textAlign: TextAlign.center),
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
      _notify(tr('无法打开这个链接'));
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        _notify(tr('无法打开这个链接'));
      }
    } catch (_) {
      if (mounted) _notify(tr('无法打开这个链接'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _providers
        .where((item) => item.id == _currentProviderId)
        .firstOrNull;
    final activeModel = _topic != null || _hasDraft;
    final title = activeModel
        ? '${provider?.name ?? '服务已删除'} · ${_currentModel ?? ''}'
        : tr('模型之间');
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: IosColors.background,
      drawer: SizedBox(
        width:
            MediaQuery.sizeOf(context).width.clamp(0.0, 420.0).toDouble() * .86,
        child: TopicScreen(
          key: ValueKey(
            Object.hashAll(
              _topics.map((topic) => Object.hash(topic.id, topic.title)),
            ),
          ),
          selectedId: _topic?.id,
          generatingTopicId: _sendingTopicId,
          onClose: _closeTopics,
          onSelect: _chooseTopic,
          onNew: _newFromDrawer,
          onSettings: _settingsFromDrawer,
          onChanged: _load,
        ),
      ),
      appBar: iosAppBar(
        title: title,
        leading: IosNavButton(
          icon: CupertinoIcons.line_horizontal_3,
          onPressed: _openTopics,
        ),
        titleWidget: ChatModelTitle(
          label: title,
          onPressed: _providers.isEmpty ? null : _changeModel,
        ),
        actions: [
          ChatMoreButton(
            onNewTopic: _newTopic,
            onModel: _changeModel,
            onProviders: _openProviders,
            canChangeModel: _providers.isNotEmpty,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : Column(
              children: [
                Expanded(
                  child: _topic == null && !_hasDraft
                      ? _welcome()
                      : _chatList(),
                ),
                if (_error != null) _errorCard(),
                _composer(),
              ],
            ),
    );
  }

  Widget _errorCard() => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    decoration: BoxDecoration(
      color: IosColors.errorSurface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(_error!),
          style: TextStyle(color: IosColors.destructive, fontSize: 13),
        ),
        if (_errorAction != _ChatErrorAction.none)
          Wrap(
            spacing: 8,
            children: [
              if (_errorAction == _ChatErrorAction.configure ||
                  _errorAction == _ChatErrorAction.request ||
                  _errorAction == _ChatErrorAction.retry)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: _editCurrentProvider,
                  child: Text(
                    _errorAction == _ChatErrorAction.configure
                        ? tr('检查密钥')
                        : tr('检查服务配置'),
                  ),
                ),
              if (_errorAction == _ChatErrorAction.retry)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: _retryReply,
                  child: Text(tr('重试回复')),
                ),
              if (_errorAction == _ChatErrorAction.model ||
                  _errorAction == _ChatErrorAction.request)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: _changeModel,
                  child: Text(tr('切换模型')),
                ),
            ],
          ),
      ],
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
            child: Icon(
              CupertinoIcons.chat_bubble_2_fill,
              color: IosColors.blue,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr('模型之间'),
            style: TextStyle(
              color: IosColors.label,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            tr('一个地方，和不同模型继续对话。'),
            textAlign: TextAlign.center,
            style: TextStyle(color: IosColors.secondary, fontSize: 15),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 225,
            child: IosPrimaryButton(
              label: _providers.isEmpty ? tr('接入模型服务') : tr('开始新对话'),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.chat_bubble_text,
              size: 40,
              color: IosColors.secondary,
            ),
            const SizedBox(height: 13),
            Text(
              tr('开始新的对话'),
              style: TextStyle(
                color: IosColors.label,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              tr('输入消息，开始讨论。'),
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
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: CupertinoActivityIndicator(radius: 10),
                    )
                  else if (user)
                    SelectableText(
                      content,
                      style: TextStyle(
                        color: IosColors.onAccent,
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
                    Padding(
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
                          if (mounted) _notify(tr('已复制'));
                        },
                        child: Icon(
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
    decoration: BoxDecoration(
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
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              textCapitalization: TextCapitalization.sentences,
              placeholder: _providers.isEmpty ? tr('先接入模型服务') : tr('发送消息'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: IosColors.surface,
                borderRadius: BorderRadius.circular(21),
                border: Border.all(color: IosColors.separator),
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
                color: IosColors.onAccent,
                size: 21,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
