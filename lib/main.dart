import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'apple_purchases.dart';
import 'purchase_screen.dart';
import 'app_platform.dart';
import 'desktop_chat.dart';
import 'app_preferences.dart';
import 'assistant_markdown.dart';
import 'chat_more_menu.dart';
import 'chat_model_selector.dart';
import 'chat_model_title.dart';
import 'chat_message_meta.dart';
import 'chat_loading_status.dart';
import 'chat_scroll.dart';
import 'data.dart';
import 'ios_style.dart';
import 'message_copy.dart';
import 'provider_screen.dart';
import 'prompt_screen.dart';
import 'privacy_screen.dart';
import 'settings_screen.dart';
import 'search_service.dart';
import 'search_settings_screen.dart';
import 'search_sources.dart';
import 'startup_screen.dart';
import 'topic_screen.dart';
import 'voice_client.dart';
import 'voice_recording.dart';
import 'voice_settings_screen.dart';
import 'voice_recording_overlay.dart';
import 'watch_chat.dart';

enum _ChatErrorAction { none, configure, model, request, retry, search }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    // Inspector paint diagnostics can persist across hot restarts in debug.
    debugPaintBaselinesEnabled = false;
    debugPaintPointersEnabled = false;
    debugPaintSizeEnabled = false;
    debugRepaintRainbowEnabled = false;
    return true;
  }());
  runApp(const ModelChatApp());
}

@pragma('vm:entry-point')
void watchBackgroundMain() => startWatchWorker();

class ModelChatApp extends StatelessWidget {
  const ModelChatApp({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (context, _) => MaterialApp(
      title: tr('AI Link'),
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
        platform: isDesktopApp ? defaultTargetPlatform : TargetPlatform.iOS,
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
        platform: isDesktopApp ? defaultTargetPlatform : TargetPlatform.iOS,
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
      home: StartupScreen(
        initialize: AppPreferences.instance.load,
        homeBuilder: (onReady) => ChatHome(onReady: onReady),
      ),
    ),
  );
}

class ChatHome extends StatefulWidget {
  const ChatHome({super.key, this.onReady});
  final VoidCallback? onReady;
  @override
  State<ChatHome> createState() => _ChatHomeState();
}

class _ChatHomeState extends State<ChatHome> with WidgetsBindingObserver {
  static const _watchUpdates = MethodChannel('between_models/watch_updates');
  static const _desktopMenu = MethodChannel('between_models/desktop_menu');
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _desktopNavigator = GlobalKey<NavigatorState>();
  final _desktopRevision = ValueNotifier<int>(0);
  DesktopSection _desktopSection = DesktopSection.chat;
  bool _desktopWide = false;
  late final _desktopObserver = DesktopNavigationObserver(() {
    if (mounted) setState(() => _desktopSection = DesktopSection.chat);
  });

  NavigatorState get _navigation =>
      isDesktopApp ? _desktopNavigator.currentState! : Navigator.of(context);

  Future<T?> _pushRoute<T>(PageRoute<T> route, {DesktopSection? section}) {
    if (isDesktopApp && section != null) {
      _inputFocus.unfocus();
      _navigation.popUntil((route) => route.isFirst);
      setState(() => _desktopSection = section);
    }
    return _navigation.push(route);
  }

  void _showDesktopChat() {
    if (!isDesktopApp) return;
    _navigation.popUntil((route) => route.isFirst);
    setState(() => _desktopSection = DesktopSection.chat);
  }

  void _selectDesktopSection(DesktopSection section) {
    switch (section) {
      case DesktopSection.chat:
        _showDesktopChat();
      case DesktopSection.providers:
        _openProviders();
      case DesktopSection.voice:
        _openVoiceSettings();
      case DesktopSection.search:
        _openSearchSettings();
      case DesktopSection.settings:
        _openSettings();
      case DesktopSection.prompts:
        _pushRoute<void>(
          appPageRoute(builder: (_) => const PromptSettingsScreen()),
          section: section,
        );
      case DesktopSection.messages:
        _pushRoute<void>(
          appPageRoute(
            builder: (_) =>
                MessageSettingsScreen(canChangeSearch: _canChangeSearch),
          ),
          section: section,
        );
      case DesktopSection.privacy:
        _pushRoute<bool>(
          appPageRoute(
            builder: (_) => PrivacyScreen(canClearData: _canClearData),
          ),
          section: section,
        ).then((cleared) async {
          if (cleared == true) {
            await AppPreferences.instance.load();
            await _load();
          }
        });
      case DesktopSection.about:
        _pushRoute<void>(
          appPageRoute(builder: (_) => const AboutScreen()),
          section: section,
        );
    }
  }

  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  PcmVoiceRecording? _pcmRecording;
  String? _playingPath;
  bool _recording = false;
  bool _voiceMode = false;
  bool _voicePointerDown = false;
  int? _voicePointer;
  double _voiceStartX = 0;
  OverlayEntry? _voiceOverlay;
  final _recordElapsedMs = ValueNotifier<int>(0);
  final _recordLevel = ValueNotifier<double>(.1);
  final _voiceReleaseAction = ValueNotifier<VoiceReleaseAction>(
    VoiceReleaseAction.send,
  );
  final _recordClock = Stopwatch();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  bool _transcribing = false;
  bool _canSpeak = false;
  int? _speechMessageId;
  SpeechPlaybackState _speechState = SpeechPlaybackState.idle;
  bool get _playing => _speechState != SpeechPlaybackState.idle;
  int _speechGeneration = 0;
  VoiceClient? _speechClient;
  StreamSubscription<void>? _playbackCompletion;
  Timer? _recordTimer;
  final _chatScroll = ChatScrollController();
  List<ProviderConfig> _providers = [];
  List<ChatTopic> _topics = [];
  List<ChatMessage> _messages = [];
  ChatTopic? _topic;
  int? _draftProviderId;
  String? _draftModel;
  ModelApiClient? _activeClient;
  final _titleClients = <ModelApiClient>{};
  String _reply = '';
  final _replyElapsedMs = ValueNotifier<int>(0);
  Timer? _replyTimer;
  String? _error;
  _ChatErrorAction _errorAction = _ChatErrorAction.none;
  bool _loading = true;
  bool _starting = false;
  bool _sending = false;
  bool _searchEnabled = false;
  bool _searching = false;
  List<SearchSource> _replySources = const [];
  StreamSubscription<void>? _watchConfigSubscription;
  bool _watchConfigPending = false;
  bool _watchConfigSyncing = false;
  bool _watchProcessing = false;
  bool _cancelRequested = false;
  int? _sendingTopicId;

  int? get _currentProviderId => _topic?.providerId ?? _draftProviderId;
  String? get _currentModel => _topic?.model ?? _draftModel;
  bool get _hasDraft => _draftProviderId != null && _draftModel != null;

  @override
  void initState() {
    super.initState();
    if (isDesktopApp) {
      _desktopMenu.setMethodCallHandler((call) async {
        if (!mounted || Navigator.of(context).canPop()) return;
        if (call.method == 'newConversation') await _newTopic();
        if (call.method == 'settings') await _openSettings();
      });
    }
    _watchUpdates.setMethodCallHandler((call) async {
      if (call.method == 'changed' && mounted && !_sending && !_starting) {
        await _load();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    ApplePurchases.instance.start();
    ApplePurchases.instance.addListener(_purchaseChanged);
    if (supportsWatchCompanion) {
      _watchConfigSubscription = ChatStore.instance.watchConfigurationChanges
          .listen((_) {
            unawaited(_syncWatchConfiguration());
          });
      unawaited(_syncWatchConfiguration());
    }
    unawaited(_removeStaleVoiceFiles(DateTime.now()));
    _playbackCompletion = _player.onPlayerComplete.listen((_) {
      final path = _playingPath;
      _playingPath = null;
      if (path != null) File(path).delete().catchError((_) => File(path));
      if (mounted) {
        setState(() {
          _speechState = SpeechPlaybackState.idle;
          _speechMessageId = null;
        });
      }
    });
    _load();
  }

  Future<void> _removeStaleVoiceFiles(DateTime startedAt) async {
    try {
      final directory = await getTemporaryDirectory();
      await for (final entity in directory.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            (name.startsWith('voice_') && name.endsWith('.wav') ||
                name.startsWith('reply_') &&
                    (name.endsWith('.wav') || name.endsWith('.mp3'))) &&
            (await entity.lastModified()).isBefore(startedAt)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Temporary files are also removed after each request and playback.
    }
  }

  @override
  void dispose() {
    if (isDesktopApp) _desktopMenu.setMethodCallHandler(null);
    _desktopRevision.dispose();
    _watchUpdates.setMethodCallHandler(null);
    unawaited(_watchConfigSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    ApplePurchases.instance.removeListener(_purchaseChanged);
    _recordTimer?.cancel();
    _hideVoiceOverlay();
    _recordElapsedMs.dispose();
    _recordLevel.dispose();
    _voiceReleaseAction.dispose();
    if (_amplitudeSubscription case final subscription?) {
      unawaited(subscription.cancel());
    }
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _speechGeneration++;
    _speechClient?.close();
    unawaited(_playbackCompletion?.cancel());
    _player.dispose();
    unawaited(_pcmRecording?.discard());
    if (_playingPath case final path?) {
      File(path).delete().catchError((_) => File(path));
    }
    _inputFocus.dispose();
    _activeClient?.cancel();
    _replyTimer?.cancel();
    _replyElapsedMs.dispose();
    for (final client in _titleClients) {
      client.cancel();
    }
    _input.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ApplePurchases.instance.refresh());
      unawaited(_syncWatchConfiguration());
    } else {
      final wasHolding = _voicePointerDown;
      _voicePointerDown = false;
      _voicePointer = null;
      _voiceReleaseAction.value = VoiceReleaseAction.send;
      _hideVoiceOverlay();
      if (wasHolding && mounted) setState(() {});
      if (_recording) unawaited(_cancelRecording());
    }
  }

  void _purchaseChanged() {
    if (mounted) {
      setState(() {});
      unawaited(_syncWatchConfiguration());
    }
  }

  Future<bool> _ensurePurchaseAccess() async {
    if (await ApplePurchases.instance.refresh()) return mounted;
    if (!mounted) return false;
    if (_voicePointerDown) _endVoicePress();
    await Navigator.push<void>(
      context,
      appPageRoute(builder: (_) => const PurchaseScreen()),
    );
    if (!mounted) return false;
    return ApplePurchases.instance.refresh();
  }

  Future<void> _syncWatchConfiguration() async {
    if (!supportsWatchCompanion) return;
    _watchConfigPending = true;
    if (_watchConfigSyncing) return;
    _watchConfigSyncing = true;
    try {
      while (mounted && _watchConfigPending) {
        _watchConfigPending = false;
        try {
          final config = await WatchChatProcessor().configuration();
          if (!mounted) return;
          await const MethodChannel(
            'between_models/companion_install',
          ).invokeMethod<void>('syncConfiguration', {'configuration': config});
        } catch (_) {
          // Pairing can be unavailable; retry on foreground or the watch's next config request.
        }
      }
    } finally {
      _watchConfigSyncing = false;
    }
  }

  Future<void> _load() async {
    final initialLoad = _loading;
    try {
      bool watchProcessing = false;
      try {
        if (supportsWatchCompanion) {
          watchProcessing =
              await _watchUpdates.invokeMethod<bool>('isProcessing') ?? false;
        }
      } on MissingPluginException {
        // Wear OS integration is only installed in the Android phone app.
      }
      final providers = await ChatStore.instance.providers();
      final store = ChatStore.instance;
      final searchEnabled = await store.setting('search_enabled') == '1';
      final ttsId = await store.setting('voice_tts_id');
      final speechService = (await store.voiceProviders())
          .where((service) => service.id == ttsId)
          .firstOrNull;
      final canSpeak =
          speechService != null &&
          speechService.ttsModel.trim().isNotEmpty &&
          speechService.voice.trim().isNotEmpty &&
          (await store.voiceApiKey(speechService))?.trim().isNotEmpty == true;
      final topics = await ChatStore.instance.topics();
      final savedSelection = _loading
          ? await ChatStore.instance.lastChatSelection()
          : null;
      final selected = _topic == null
          ? null
          : topics.where((item) => item.id == _topic!.id).firstOrNull;
      final messages = selected == null
          ? <ChatMessage>[]
          : await ChatStore.instance.messages(selected.id);
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _searchEnabled = searchEnabled;
        _canSpeak = canSpeak;
        _watchProcessing = watchProcessing;
        _topics = topics;
        _topic = selected;
        if (_topic == null &&
            (initialLoad ||
                _draftProviderId != null &&
                    !providers.any((item) => item.id == _draftProviderId))) {
          final selection = initialChatSelection(
            providers,
            topics,
            savedSelection,
          );
          _draftProviderId = selection?.providerId;
          _draftModel = selection?.model;
        }
        _messages = messages;
        _loading = false;
      });
      _chatScroll.scrollToLatest(force: initialLoad);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开本地数据：$error';
          _errorAction = _ChatErrorAction.none;
        });
      }
    } finally {
      if (initialLoad && mounted) widget.onReady?.call();
    }
  }

  Future<void> _openProviders() async {
    await _pushRoute<bool>(
      appPageRoute(builder: (_) => ProviderScreen(canClearData: _canClearData)),
      section: DesktopSection.providers,
    );
    await _load();
  }

  Future<void> _openSettings() async {
    await _pushRoute<void>(
      appPageRoute(builder: (_) => SettingsScreen(canClearData: _canClearData)),
      section: DesktopSection.settings,
    );
    await _load();
  }

  Future<void> _openSearchSettings() async {
    await _pushRoute<void>(
      appPageRoute(builder: (_) => const SearchSettingsScreen()),
      section: DesktopSection.search,
    );
    await _load();
  }

  bool _canChangeSearch() =>
      !_sending && !_starting && !_recording && !_transcribing;

  Future<void> _openMessageSettings() async {
    await _pushRoute<void>(
      appPageRoute(
        builder: (_) =>
            MessageSettingsScreen(canChangeSearch: _canChangeSearch),
      ),
    );
    await _load();
  }

  Future<void> _openModelSettings() async {
    await _pushRoute<void>(
      appPageRoute(
        builder: (_) => ModelSettingsScreen(
          canClearData: _canClearData,
          onPrivacy: _openPrivacy,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openPrivacy() async {
    final cleared = await _pushRoute<bool>(
      appPageRoute(builder: (_) => PrivacyScreen(canClearData: _canClearData)),
    );
    if (cleared == true) await AppPreferences.instance.load();
  }

  Future<void> _openVoiceSettings() async {
    await _pushRoute<void>(
      appPageRoute(builder: (_) => const VoiceSettingsScreen()),
      section: DesktopSection.voice,
    );
    await _load();
  }

  void _openTopics() => _scaffoldKey.currentState?.openDrawer();

  bool _canClearData() =>
      !_sending &&
      !_watchProcessing &&
      !_starting &&
      !_recording &&
      !_transcribing &&
      !_playing &&
      _titleClients.isEmpty;

  void _closeTopics() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  Future<void> _chooseTopic(int id) async {
    _closeTopics();
    _showDesktopChat();
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
    _showDesktopChat();
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
      _replySources = const [];
      _searching = false;
      _error = null;
      _errorAction = _ChatErrorAction.none;
    });
    await ChatStore.instance.saveLastChatSelection(
      ChatSelection(provider.id, model),
    );
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
    if (topic.providerId case final providerId?) {
      await ChatStore.instance.saveLastChatSelection(
        ChatSelection(providerId, topic.model),
      );
    }
    _chatScroll.scrollToLatest(force: true);
  }

  Future<void> _changeModel() async {
    final topic = _topic;
    if (_providers.isEmpty) {
      await _openModelSettings();
      return;
    }
    if (_sending || _starting) {
      _notify(tr('请先停止当前回复，再切换模型'));
      return;
    }
    final selection = await _pushRoute<ChatModelSelection>(
      appPageRoute(
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
    await ChatStore.instance.saveLastChatSelection(
      ChatSelection(selection.providerId, selection.model),
    );
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
    final changed = await _pushRoute<bool>(
      appPageRoute(builder: (_) => ProviderEditor(config: provider)),
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

  Future<VoiceProviderConfig?> _selectedVoiceService(
    String settingKey, {
    bool openSettings = true,
  }) async {
    final store = ChatStore.instance;
    final id = await store.setting(settingKey);
    final service = (await store.voiceProviders())
        .where((item) => item.id == id)
        .firstOrNull;
    if (service == null && openSettings && mounted) {
      await _pushRoute<void>(
        appPageRoute(builder: (_) => const VoiceSettingsScreen()),
      );
    }
    return service;
  }

  Future<void> _startRecording() async {
    if (!_voicePointerDown ||
        _recording ||
        _transcribing ||
        _sending ||
        _starting) {
      return;
    }
    if (await _selectedVoiceService('voice_asr_id', openSettings: false) ==
        null) {
      _endVoicePress();
      if (mounted) await _selectedVoiceService('voice_asr_id');
      return;
    }
    try {
      if (!await _ensurePurchaseAccess()) return;
      if (!await _recorder.hasPermission()) {
        _endVoicePress();
        if (mounted) {
          _notify(tr('请允许麦克风权限后重试'));
        }
        return;
      }
      if (!_voicePointerDown || !mounted) return;
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      final recording = PcmVoiceRecording(stream);
      if (!mounted) {
        await _recorder.cancel();
        await recording.discard();
        return;
      }
      setState(() {
        _recording = true;
        _pcmRecording = recording;
      });
      if (!_voicePointerDown) {
        await _cancelRecording();
        return;
      }
      _recordClock
        ..reset()
        ..start();
      _recordElapsedMs.value = 0;
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            if (!amplitude.current.isFinite) return;
            final next = ((amplitude.current + 55) / 55)
                .clamp(.05, 1.0)
                .toDouble();
            _recordLevel.value = _recordLevel.value * .45 + next * .55;
          }, onError: (_) {});
      _recordTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        _recordElapsedMs.value = _recordClock.elapsedMilliseconds;
        if (_recordElapsedMs.value >= 60000) {
          _completeVoiceRecording();
        }
      });
    } catch (_) {
      _endVoicePress();
      if (mounted) {
        _notify(tr('无法开始录音，请检查麦克风权限'));
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    _recordClock.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (mounted) {
      setState(() {
        _recording = false;
      });
    }
    final recording = _pcmRecording;
    _pcmRecording = null;
    await _recorder.cancel();
    await recording?.discard();
  }

  Future<void> _finishRecording({required bool reviewBeforeSending}) async {
    if (!_recording) return;
    if (_recordClock.elapsedMilliseconds < 600) {
      await _cancelRecording();
      return;
    }
    _recordTimer?.cancel();
    _recordClock.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    setState(() {
      _recording = false;
      _transcribing = true;
    });
    final recording = _pcmRecording;
    _pcmRecording = null;
    VoiceClient? client;
    var sendAfterTranscription = false;
    try {
      await _recorder.stop();
      if (recording == null) throw const VoiceException('录音采集失败，请重试');
      final data = await recording.finish();
      final service = await _selectedVoiceService(
        'voice_asr_id',
        openSettings: false,
      );
      if (service == null) throw const VoiceException('请先选择语音识别服务');
      final key = await ChatStore.instance.voiceApiKey(service);
      if (key == null || key.isEmpty) {
        throw const VoiceException('语音服务缺少 API Key');
      }
      if (!await _ensurePurchaseAccess()) return;
      client = VoiceClient(service, key);
      final transcript = await client.transcribe(data);
      if (!mounted) return;
      sendAfterTranscription = !reviewBeforeSending;
      final old = _input.text.trim();
      _input.text = old.isEmpty ? transcript : '$old\n$transcript';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      if (!sendAfterTranscription) {
        setState(() => _voiceMode = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocus.requestFocus();
        });
      }
    } catch (error) {
      if (mounted) {
        _notify(error is VoiceException ? tr(error.message) : tr('语音识别失败，请重试'));
      }
    } finally {
      client?.close();
      await recording?.discard();
      if (mounted) setState(() => _transcribing = false);
    }
    if (sendAfterTranscription && mounted) await _send();
  }

  void _voiceDown(PointerDownEvent event) {
    if (_voicePointerDown ||
        _recording ||
        _transcribing ||
        _sending ||
        _starting) {
      return;
    }
    _voicePointerDown = true;
    _voicePointer = event.pointer;
    _voiceReleaseAction.value = VoiceReleaseAction.send;
    _voiceStartX = event.position.dx;
    setState(() {});
    _showVoiceOverlay();
    unawaited(_startRecording());
  }

  void _voiceMove(PointerMoveEvent event) {
    if (!_voicePointerDown || event.pointer != _voicePointer) return;
    _voiceReleaseAction.value = VoiceReleaseAction.fromDrag(
      event.position.dx - _voiceStartX,
    );
  }

  void _voiceUp(PointerUpEvent event) {
    if (!_voicePointerDown || event.pointer != _voicePointer) return;
    _voiceReleaseAction.value = VoiceReleaseAction.fromDrag(
      event.position.dx - _voiceStartX,
    );
    _completeVoiceRecording();
  }

  void _completeVoiceRecording() {
    if (!_voicePointerDown) return;
    final action = _voiceReleaseAction.value;
    _endVoicePress();
    if (_recording) {
      unawaited(
        action == VoiceReleaseAction.cancel
            ? _cancelRecording()
            : _finishRecording(
                reviewBeforeSending: action == VoiceReleaseAction.review,
              ),
      );
    }
  }

  void _voiceCancel(PointerCancelEvent event) {
    if (event.pointer != _voicePointer) return;
    _endVoicePress();
    if (_recording) unawaited(_cancelRecording());
  }

  void _showVoiceOverlay() {
    _hideVoiceOverlay();
    _voiceOverlay = OverlayEntry(
      builder: (_) => VoiceRecordingOverlay(
        elapsedMs: _recordElapsedMs,
        level: _recordLevel,
        releaseAction: _voiceReleaseAction,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_voiceOverlay!);
  }

  void _hideVoiceOverlay() {
    _voiceOverlay?.remove();
    _voiceOverlay?.dispose();
    _voiceOverlay = null;
  }

  void _endVoicePress() {
    _voicePointerDown = false;
    _voicePointer = null;
    _voiceReleaseAction.value = VoiceReleaseAction.send;
    _hideVoiceOverlay();
    if (mounted) setState(() {});
  }

  void _toggleVoiceMode() {
    if (_recording || _voicePointerDown) return;
    setState(() => _voiceMode = !_voiceMode);
    if (_voiceMode) {
      _inputFocus.unfocus();
    }
  }

  Future<void> _playSpeech(String markdown, {required int messageId}) async {
    if (_speechState == SpeechPlaybackState.loading) return;
    if (_playing) {
      final generation = ++_speechGeneration;
      final oldPath = _playingPath;
      _playingPath = null;
      setState(() => _speechState = SpeechPlaybackState.loading);
      try {
        await _player.stop();
      } finally {
        if (oldPath != null) {
          await File(oldPath).delete().catchError((_) => File(oldPath));
        }
        if (mounted && generation == _speechGeneration) {
          setState(() {
            _speechState = SpeechPlaybackState.idle;
            _speechMessageId = null;
          });
        }
      }
      return;
    }
    if (!_canSpeak || !mounted) return;
    if (!await _ensurePurchaseAccess()) return;
    final generation = ++_speechGeneration;
    setState(() {
      _speechState = SpeechPlaybackState.loading;
      _speechMessageId = messageId;
    });
    VoiceClient? client;
    String? path;
    try {
      final service = await _selectedVoiceService(
        'voice_tts_id',
        openSettings: false,
      );
      if (service == null) return;
      final key = await ChatStore.instance.voiceApiKey(service);
      if (key == null || key.isEmpty) {
        throw const VoiceException('语音服务缺少 API Key');
      }
      if (!mounted || generation != _speechGeneration) return;
      client = VoiceClient(service, key);
      _speechClient = client;
      final bytes = await client.synthesize(readableMarkdown(markdown));
      if (!mounted || generation != _speechGeneration) return;
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/reply_${DateTime.now().microsecondsSinceEpoch}.${service.protocol == VoiceProtocol.mimo ? 'wav' : 'mp3'}';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted || generation != _speechGeneration) return;
      _playingPath = path;
      await _player.play(DeviceFileSource(path));
      if (mounted && generation == _speechGeneration && _playingPath == path) {
        setState(() => _speechState = SpeechPlaybackState.playing);
      }
    } catch (error) {
      if (mounted && generation == _speechGeneration) {
        _playingPath = null;
        setState(() {
          _speechState = SpeechPlaybackState.idle;
          _speechMessageId = null;
        });
        _notify(error is VoiceException ? tr(error.message) : tr('语音朗读失败，请重试'));
      }
    } finally {
      client?.close();
      if (path != null && path != _playingPath) {
        await File(path).delete().catchError((_) => File(path!));
      }
      if (mounted &&
          generation == _speechGeneration &&
          _speechState == SpeechPlaybackState.loading) {
        setState(() {
          _speechState = SpeechPlaybackState.idle;
          _speechMessageId = null;
        });
      }
    }
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty ||
        _starting ||
        _sending ||
        _recording ||
        _transcribing) {
      return;
    }
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
    if (!await _ensurePurchaseAccess()) return;
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
      await ChatStore.instance.addMessage(
        topic.id,
        'user',
        content,
        modelId: model,
        provider: provider,
      );
      if (first) {
        await ChatStore.instance.updateTopic(
          topic.id,
          title: initialTopicTitle(content),
        );
      }
    }
    await ChatStore.instance.saveLastChatSelection(
      ChatSelection(provider.id, model),
    );
    _input.clear();
    final history = await ChatStore.instance.messages(topic.id);
    await _requestReply(topic, provider, key, systemPrompt, history);
  }

  Future<void> _retryReply() async {
    final topic = _topic;
    if (topic == null || _starting || _sending) return;
    if (!await _ensurePurchaseAccess()) return;
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
      _replySources = const [];
      _searching = _searchEnabled;
      _replyElapsedMs.value = 0;
      _error = null;
      _errorAction = _ChatErrorAction.none;
      _cancelRequested = false;
    });
    _chatScroll.scrollToLatest(force: true);
    final client = ModelApiClient(provider, key);
    _activeClient = client;
    var answer = '';
    var completed = false;
    final watch = Stopwatch()..start();
    _replyTimer?.cancel();
    _replyTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _sendingTopicId == topic.id) {
        _replyElapsedMs.value = watch.elapsedMilliseconds;
      }
    });
    int? firstTokenMs;
    ReplyUsage? usage;
    List<SearchSource> sources = const [];
    final searchEnabled = _searchEnabled;
    try {
      await _refreshTopics();
      ({SearchProviderConfig config, String apiKey})? webSearch;
      if (searchEnabled) {
        final config = await ChatStore.instance.selectedSearchProvider();
        final searchKey = config == null
            ? null
            : await ChatStore.instance.searchApiKey(config.id);
        if (config == null || searchKey == null || searchKey.isEmpty) {
          throw const SearchException('请先配置搜索服务 API Key。');
        }
        webSearch = (config: config, apiKey: searchKey);
      }
      await for (final chunk in client.streamReply(
        history,
        topic.model,
        systemPrompt: systemPrompt,
        webSearch: webSearch,
        onSearchResults: (results) {
          sources = results;
          if (mounted) {
            setState(() {
              _replySources = results;
              _searching = false;
            });
          }
        },
        onUsage: (reported) {
          usage = (usage ?? const ReplyUsage()).merge(reported);
        },
      )) {
        answer += chunk;
        firstTokenMs ??= watch.elapsedMilliseconds;
        if (mounted && _topic?.id == topic.id) {
          setState(() {
            _reply = answer;
          });
          _chatScroll.scrollToLatest();
        }
      }
      completed = !_cancelRequested;
    } catch (error) {
      if (!_cancelRequested && mounted && _topic?.id == topic.id) {
        setState(() {
          _error = error.toString();
          _errorAction = error is SearchException
              ? _ChatErrorAction.search
              : error is ApiException
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
      watch.stop();
      _replyTimer?.cancel();
      _replyTimer = null;
      client.cancel();
      _activeClient = null;
      int? answerMessageId;
      if (answer.isNotEmpty) {
        answerMessageId = await ChatStore.instance.addMessage(
          topic.id,
          'assistant',
          answer,
          modelId: topic.model,
          provider: provider,
          firstTokenMs: firstTokenMs,
          totalMs: watch.elapsedMilliseconds,
          inputTokens: usage?.inputTokens,
          outputTokens: usage?.outputTokens,
          searchSources: sources,
        );
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
          _replySources = const [];
          _searching = false;
          _replyElapsedMs.value = 0;
        });
        if (_topic?.id == topic.id) {
          final messages = await ChatStore.instance.messages(topic.id);
          if (mounted) setState(() => _messages = messages);
          _chatScroll.scrollToLatest();
        }
        await _refreshTopics();
      }
      if (shouldGenerateTitle && mounted) {
        unawaited(
          _generateTitle(topic, provider, key, history.first.content, answer),
        );
      }
      if (completed &&
          answer.isNotEmpty &&
          mounted &&
          !_playing &&
          answerMessageId != null &&
          AppPreferences.instance.autoReadReplies) {
        unawaited(_playSpeech(answer, messageId: answerMessageId));
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
    if (!await ApplePurchases.instance.refresh()) return;
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

  Widget _topicsPanel({bool persistent = false}) => TopicScreen(
    key: ValueKey(
      Object.hashAll(
        _topics.map((topic) => Object.hash(topic.id, topic.title)),
      ),
    ),
    persistent: persistent,
    selectedId: _topic?.id,
    generatingTopicId: _sendingTopicId,
    onClose: _closeTopics,
    onSelect: _chooseTopic,
    onNew: _newFromDrawer,
    onSettings: _settingsFromDrawer,
    onChanged: _load,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = isDesktopApp && constraints.maxWidth >= 900;
      if (!isDesktopApp) return _buildChat(context, false);
      _desktopWide = wide;
      _desktopRevision.value++;
      bool current() =>
          !Navigator.of(context).canPop() && !_navigation.canPop();
      return DesktopChatKeyboard(
        controller: _input,
        inputFocus: _inputFocus,
        onSend: () {
          if (current() && !_voiceMode) _send();
        },
        onNew: _newTopic,
        onSettings: _openSettings,
        child: DesktopChatLayout(
          showSidebar: wide,
          sidebar: _desktopSection == DesktopSection.chat
              ? _topicsPanel(persistent: true)
              : DesktopNavigationMenu(
                  selected: _desktopSection,
                  onSelect: _selectDesktopSection,
                ),
          chat: Navigator(
            key: _desktopNavigator,
            observers: [_desktopObserver],
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (context, _, _) => ValueListenableBuilder<int>(
                valueListenable: _desktopRevision,
                builder: (context, _, _) => _buildChat(context, _desktopWide),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildChat(BuildContext context, bool wide) {
    final provider = _providers
        .where((item) => item.id == _currentProviderId)
        .firstOrNull;
    final activeModel = _topic != null || _hasDraft;
    final title = activeModel
        ? '${provider?.name ?? '服务已删除'} · ${_currentModel ?? ''}'
        : tr('AI Link');
    return Scaffold(
      key: _scaffoldKey,
      // Subscribe to theme changes so the entire chat follows system appearance.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: wide
          ? null
          : SizedBox(
              width:
                  MediaQuery.sizeOf(context).width
                      .clamp(0.0, 420.0)
                      .toDouble() *
                  .86,
              child: _topicsPanel(),
            ),
      appBar: iosAppBar(
        title: title,
        backgroundColor: IosColors.chatChrome,
        leading: wide
            ? null
            : IosNavButton(
                icon: CupertinoIcons.line_horizontal_3,
                onPressed: _openTopics,
              ),
        titleWidget: ChatModelTitle(
          label: title,
          providerName: provider?.name,
          providerPresetId: provider == null
              ? null
              : presetForProvider(provider)?.id,
          onPressed: _providers.isEmpty ? null : _changeModel,
        ),
        actions: [
          ChatMoreButton(
            onNewTopic: _newTopic,
            onModel: _changeModel,
            onModelSettings: _openModelSettings,
            onVoiceSettings: _openVoiceSettings,
            onSearch: _openSearchSettings,
            onMessageSettings: _openMessageSettings,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: isDesktopApp ? 960 : double.infinity,
          child: _loading
              ? const Center(child: CupertinoActivityIndicator(radius: 14))
              : Column(
                  children: [
                    Expanded(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => _inputFocus.unfocus(),
                        child: _topic == null && !_hasDraft
                            ? _welcome()
                            : _chatList(),
                      ),
                    ),
                    if (_error != null) _errorCard(),
                    _composer(),
                  ],
                ),
        ),
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
              if (_errorAction == _ChatErrorAction.search)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: _openSearchSettings,
                  child: Text(tr('检查搜索配置')),
                ),
              if (_errorAction == _ChatErrorAction.retry ||
                  _errorAction == _ChatErrorAction.search)
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
          SizedBox(
            width: 76,
            height: 76,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/branding/ai_link_icon_source.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr('AI Link'),
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
    return NotificationListener<ScrollNotification>(
      onNotification: _chatScroll.onScrollNotification,
      child: ListView.builder(
        controller: _chatScroll.controller,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        itemCount: count,
        itemBuilder: (context, index) {
          if (index == _messages.length) {
            return _bubble(
              'assistant',
              _reply,
              loading: true,
              searchSources: _replySources,
            );
          }
          final message = _messages[index];
          return _bubble(
            message.role,
            message.content,
            messageId: message.id,
            searchSources: message.searchSources,
            providerName: message.providerName,
            providerPresetId: message.providerPresetId,
            modelId: message.modelId,
            firstTokenMs: message.firstTokenMs,
            totalMs: message.totalMs,
            usage: ReplyUsage(
              inputTokens: message.inputTokens,
              outputTokens: message.outputTokens,
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyBubble(
    String content, {
    required bool renderMarkdown,
  }) async {
    final format = await showAppModalPopup<MessageCopyFormat>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('复制消息')),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, MessageCopyFormat.markdown),
            child: Text(tr('复制 Markdown 原文')),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.pop(sheetContext, MessageCopyFormat.formatted),
            child: Text(tr('复制格式化文本')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (format == null) return;
    try {
      await copyMessage(content, format, renderMarkdown: renderMarkdown);
      if (mounted) _notify(tr('已复制'));
    } catch (_) {
      if (mounted) _notify(tr('复制失败'));
    }
  }

  Widget _bubble(
    String role,
    String content, {
    bool loading = false,
    int? messageId,
    String? providerName,
    String? providerPresetId,
    String? modelId,
    int? firstTokenMs,
    int? totalMs,
    ReplyUsage? usage,
    List<SearchSource> searchSources = const [],
  }) {
    final user = role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width * .86).clamp(
                  0.0,
                  760.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: user
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IosChatBubble(
                    user: user,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (content.isEmpty)
                          const SizedBox.shrink()
                        else if (user)
                          SelectableText(
                            content,
                            style: TextStyle(
                              color: IosColors.userBubbleText,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          )
                        else if (content.isNotEmpty)
                          AssistantMarkdown(
                            data: content,
                            onTapLink: _openMarkdownLink,
                          ),
                        if (loading)
                          Padding(
                            padding: EdgeInsets.only(
                              top: content.isEmpty ? 2 : 8,
                              bottom: content.isEmpty ? 2 : 0,
                            ),
                            child: ChatLoadingStatus(
                              elapsedMilliseconds: _replyElapsedMs,
                              label: _searching ? '正在搜索网页…' : '加载中',
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!user && searchSources.isNotEmpty)
                    SearchSources(
                      key: ValueKey('sources_${messageId ?? 'live'}'),
                      sources: searchSources,
                      onOpen: _openMarkdownLink,
                    ),
                  if (!loading)
                    ChatMessageMeta(
                      assistant: !user,
                      content: content,
                      providerName: providerName,
                      providerPresetId: providerPresetId,
                      modelId: modelId,
                      firstTokenMs: firstTokenMs,
                      totalMs: totalMs,
                      inputTokens: usage?.inputTokens,
                      outputTokens: usage?.outputTokens,
                      onCopy: () => _copyBubble(content, renderMarkdown: !user),
                      speechState: messageId == _speechMessageId
                          ? _speechState
                          : SpeechPlaybackState.idle,
                      speechEnabled:
                          !_playing ||
                          (messageId == _speechMessageId &&
                              _speechState == SpeechPlaybackState.playing),
                      onSpeak: user || !_canSpeak || messageId == null
                          ? null
                          : () => _playSpeech(content, messageId: messageId),
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
      color: IosColors.chatChrome,
      border: Border(top: BorderSide(color: IosColors.separator, width: .5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(46, 44),
            onPressed: _transcribing ? null : _toggleVoiceMode,
            child: Icon(
              _voiceMode ? CupertinoIcons.keyboard : CupertinoIcons.mic,
              color: _transcribing ? IosColors.secondary : IosColors.blue,
              size: 27,
              semanticLabel: tr(_voiceMode ? '切换到文字输入' : '切换到语音输入'),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _voiceMode
                ? Semantics(
                    button: true,
                    enabled: !_transcribing,
                    label: _transcribing
                        ? tr('正在识别语音…')
                        : tr('按住说话，松开发送，左滑取消，右滑转文字'),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _transcribing ? null : _voiceDown,
                      onPointerMove: _transcribing ? null : _voiceMove,
                      onPointerUp: _transcribing ? null : _voiceUp,
                      onPointerCancel: _transcribing ? null : _voiceCancel,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _voicePointerDown
                              ? IosColors.blue.withValues(alpha: .22)
                              : IosColors.assistant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: IosColors.separator),
                        ),
                        child: Text(
                          tr(_transcribing ? '正在识别语音…' : '按住说话'),
                          style: TextStyle(
                            color: _transcribing
                                ? IosColors.secondary
                                : IosColors.label,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                : CupertinoTextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 5,
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: isDesktopApp
                        ? TextInputAction.newline
                        : TextInputAction.send,
                    onSubmitted: isDesktopApp ? null : (_) => _send(),
                    textCapitalization: TextCapitalization.sentences,
                    placeholder: _providers.isEmpty
                        ? tr('先接入模型服务')
                        : tr(isDesktopApp ? '发送消息，Shift+Enter 换行' : '发送消息'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: IosColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: IosColors.separator),
                    ),
                  ),
          ),
          if (!_voiceMode || _sending) ...[
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              onPressed: _sending
                  ? _stopReply
                  : (_starting || _recording || _transcribing ? null : _send),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _sending
                      ? IosColors.destructive
                      : _starting
                      ? IosColors.secondary
                      : IosColors.blue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _sending ? CupertinoIcons.stop_fill : CupertinoIcons.arrow_up,
                  color: IosColors.onAccent,
                  size: 21,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
