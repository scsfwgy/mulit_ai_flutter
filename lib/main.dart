import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
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
import 'settings_screen.dart';
import 'topic_screen.dart';
import 'voice_client.dart';
import 'voice_settings_screen.dart';
import 'voice_send_preference.dart';
import 'voice_recording_overlay.dart';
import 'watch_chat.dart';
import 'watch_settings_screen.dart';

enum _ChatErrorAction { none, configure, model, request, retry }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    // Inspector paint diagnostics can persist across hot restarts in debug.
    debugPaintBaselinesEnabled = false;
    debugPaintPointersEnabled = false;
    debugPaintSizeEnabled = false;
    debugRepaintRainbowEnabled = false;
    return true;
  }());
  try {
    await AppPreferences.instance.load();
  } catch (_) {
    // ChatHome reports storage errors; keep the app open with default appearance.
  }
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

class _ChatHomeState extends State<ChatHome> with WidgetsBindingObserver {
  static const _watchUpdates = MethodChannel('between_models/watch_updates');
  static const _companionInstall = MethodChannel(
    'between_models/companion_install',
  );
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String? _recordingPath;
  String? _playingPath;
  bool _recording = false;
  bool _voiceMode = false;
  bool _voicePointerDown = false;
  bool _voiceCancelOnRelease = false;
  double _voiceStartY = 0;
  OverlayEntry? _voiceOverlay;
  final _recordElapsedMs = ValueNotifier<int>(0);
  final _recordLevel = ValueNotifier<double>(.1);
  final _voiceCancelling = ValueNotifier<bool>(false);
  final _recordClock = Stopwatch();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  bool _transcribing = false;
  bool _playing = false;
  int _speechGeneration = 0;
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
  bool _watchProcessing = false;
  bool _cancelRequested = false;
  bool _watchInstallChecked = false;
  int? _sendingTopicId;

  int? get _currentProviderId => _topic?.providerId ?? _draftProviderId;
  String? get _currentModel => _topic?.model ?? _draftModel;
  bool get _hasDraft => _draftProviderId != null && _draftModel != null;

  @override
  void initState() {
    super.initState();
    _watchUpdates.setMethodCallHandler((call) async {
      if (call.method == 'changed' && mounted && !_sending && !_starting) {
        await _load();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    unawaited(_removeStaleVoiceFiles(DateTime.now()));
    _player.onPlayerComplete.listen((_) {
      final path = _playingPath;
      _playingPath = null;
      if (path != null) File(path).delete().catchError((_) => File(path));
      if (mounted) setState(() => _playing = false);
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
    _watchUpdates.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    _hideVoiceOverlay();
    _recordElapsedMs.dispose();
    _recordLevel.dispose();
    _voiceCancelling.dispose();
    if (_amplitudeSubscription case final subscription?) {
      unawaited(subscription.cancel());
    }
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _player.dispose();
    if (_recordingPath case final path?) {
      File(path).delete().catchError((_) => File(path));
    }
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
    if (state != AppLifecycleState.resumed) {
      final wasHolding = _voicePointerDown;
      _voicePointerDown = false;
      _voiceCancelOnRelease = false;
      _voiceCancelling.value = false;
      _hideVoiceOverlay();
      if (wasHolding && mounted) setState(() {});
      if (_recording) unawaited(_cancelRecording());
    }
  }

  Future<void> _load() async {
    try {
      bool watchProcessing = false;
      try {
        watchProcessing =
            await _watchUpdates.invokeMethod<bool>('isProcessing') ?? false;
      } on MissingPluginException {
        // Wear OS integration is only installed in the Android phone app.
      }
      final providers = await ChatStore.instance.providers();
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
      final initialLoad = _loading;
      setState(() {
        _providers = providers;
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
      if (initialLoad && !_watchInstallChecked) {
        _watchInstallChecked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_offerWatchInstall());
        });
      }
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

  Future<void> _offerWatchInstall() async {
    try {
      final status = await _companionInstall.invokeMapMethod<String, dynamic>(
        'watchStatus',
      );
      final missing = (status?['missing'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => item['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (missing.isEmpty || !mounted) return;
      final rawDismissed = await ChatStore.instance.setting(
        'watch_install_prompt_dismissed',
      );
      final dismissed = <String>{};
      if (rawDismissed != null) {
        try {
          dismissed.addAll(
            (jsonDecode(rawDismissed) as List<dynamic>).whereType<String>(),
          );
        } catch (_) {
          // Ignore an invalid optional reminder preference.
        }
      }
      if (missing.difference(dismissed).isEmpty || !mounted) return;
      final install = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(tr('手表端尚未安装')),
          content: Text(tr('检测到已连接的 Wear OS 手表。安装手表应用后，可在手表上语音提问。')),
          actions: [
            CupertinoDialogAction(
              child: Text(tr('稍后')),
              onPressed: () => Navigator.pop(context, false),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: Text(tr('去安装')),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (install == true) {
        await Navigator.push<void>(
          context,
          CupertinoPageRoute(builder: (_) => const WatchSettingsScreen()),
        );
      } else {
        await ChatStore.instance.saveSetting(
          'watch_install_prompt_dismissed',
          jsonEncode({...dismissed, ...missing}.toList()),
        );
      }
    } catch (_) {
      // Companion discovery should never interrupt chat startup.
    }
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
      await Navigator.push<void>(
        context,
        CupertinoPageRoute(builder: (_) => const VoiceSettingsScreen()),
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
      if (!await _recorder.hasPermission()) {
        _endVoicePress();
        if (mounted) {
          _notify(tr('请允许麦克风权限后重试'));
        }
        return;
      }
      if (!_voicePointerDown || !mounted) return;
      final dir = await getTemporaryDirectory();
      if (!_voicePointerDown || !mounted) return;
      final path =
          '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _recordingPath = path;
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
          _endVoicePress();
          unawaited(_finishRecording());
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
    await _recorder.cancel();
    final path = _recordingPath;
    _recordingPath = null;
    if (path != null) await File(path).delete().catchError((_) => File(path));
  }

  Future<void> _finishRecording() async {
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
    final path = _recordingPath;
    _recordingPath = null;
    VoiceClient? client;
    var sendAfterTranscription = false;
    try {
      final stopped = await _recorder.stop();
      final file = File(stopped ?? path ?? '');
      if (!await file.exists()) throw const VoiceException('录音文件不存在，请重试');
      final data = await file.readAsBytes();
      final service = await _selectedVoiceService(
        'voice_asr_id',
        openSettings: false,
      );
      if (service == null) throw const VoiceException('请先选择语音识别服务');
      final key = await ChatStore.instance.voiceApiKey(service);
      if (key == null || key.isEmpty) {
        throw const VoiceException('语音服务缺少 API Key');
      }
      client = VoiceClient(service, key);
      final transcript = await client.transcribe(data);
      if (!mounted) return;
      sendAfterTranscription = VoiceSendPreference.autoSend(
        await ChatStore.instance.setting(VoiceSendPreference.key),
      );
      final old = _input.text.trim();
      _input.text = old.isEmpty ? transcript : '$old\n$transcript';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      if (!sendAfterTranscription) {
        setState(() => _voiceMode = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocus.requestFocus();
        });
        _notify(tr('识别完成，请检查文字后发送'));
      }
    } catch (error) {
      if (mounted) {
        _notify(error is VoiceException ? tr(error.message) : tr('语音识别失败，请重试'));
      }
    } finally {
      client?.close();
      if (path != null) await File(path).delete().catchError((_) => File(path));
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
    _voiceCancelOnRelease = false;
    _voiceCancelling.value = false;
    _voiceStartY = event.position.dy;
    setState(() {});
    _showVoiceOverlay();
    unawaited(_startRecording());
  }

  void _voiceMove(PointerMoveEvent event) {
    if (!_voicePointerDown) return;
    final cancel = event.position.dy < _voiceStartY - 60;
    if (cancel != _voiceCancelOnRelease) {
      _voiceCancelling.value = cancel;
      setState(() => _voiceCancelOnRelease = cancel);
    }
  }

  void _voiceUp() {
    if (!_voicePointerDown) return;
    _voicePointerDown = false;
    final cancel = _voiceCancelOnRelease;
    _endVoicePress();
    if (_recording) unawaited(cancel ? _cancelRecording() : _finishRecording());
  }

  void _voiceCancel() {
    _endVoicePress();
    if (_recording) unawaited(_cancelRecording());
  }

  void _showVoiceOverlay() {
    _hideVoiceOverlay();
    _voiceOverlay = OverlayEntry(
      builder: (_) => VoiceRecordingOverlay(
        elapsedMs: _recordElapsedMs,
        level: _recordLevel,
        cancelling: _voiceCancelling,
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
    _voiceCancelOnRelease = false;
    _voiceCancelling.value = false;
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

  Future<void> _playSpeech(String markdown, {bool automatic = false}) async {
    if (_playing) {
      _speechGeneration++;
      await _player.stop();
      final oldPath = _playingPath;
      _playingPath = null;
      if (oldPath != null) {
        await File(oldPath).delete().catchError((_) => File(oldPath));
      }
      if (mounted) setState(() => _playing = false);
      return;
    }
    final generation = ++_speechGeneration;
    final service = await _selectedVoiceService(
      'voice_tts_id',
      openSettings: !automatic,
    );
    if (service == null) return;
    VoiceClient? client;
    try {
      final key = await ChatStore.instance.voiceApiKey(service);
      if (key == null || key.isEmpty) {
        throw const VoiceException('语音服务缺少 API Key');
      }
      client = VoiceClient(service, key);
      if (mounted) setState(() => _playing = true);
      final bytes = await client.synthesize(readableMarkdown(markdown));
      if (!mounted || generation != _speechGeneration) return;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/reply_${DateTime.now().microsecondsSinceEpoch}.${service.protocol == VoiceProtocol.mimo ? 'wav' : 'mp3'}';
      await File(path).writeAsBytes(bytes, flush: true);
      _playingPath = path;
      await _player.play(DeviceFileSource(path));
    } catch (error) {
      final failedPath = _playingPath;
      _playingPath = null;
      if (failedPath != null) {
        await File(failedPath).delete().catchError((_) => File(failedPath));
      }
      if (mounted) {
        _notify(error is VoiceException ? tr(error.message) : tr('语音朗读失败，请重试'));
      }
      if (mounted) setState(() => _playing = false);
    } finally {
      client?.close();
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
    try {
      await _refreshTopics();
      await for (final chunk in client.streamReply(
        history,
        topic.model,
        systemPrompt: systemPrompt,
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
      watch.stop();
      _replyTimer?.cancel();
      _replyTimer = null;
      _activeClient = null;
      if (answer.isNotEmpty) {
        await ChatStore.instance.addMessage(
          topic.id,
          'assistant',
          answer,
          modelId: topic.model,
          provider: provider,
          firstTokenMs: firstTokenMs,
          totalMs: watch.elapsedMilliseconds,
          inputTokens: usage?.inputTokens,
          outputTokens: usage?.outputTokens,
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
          await ChatStore.instance.setting('voice_auto_read') == '1') {
        unawaited(_playSpeech(answer, automatic: true));
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
        : tr('AI Link');
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
            return _bubble('assistant', _reply, loading: true);
          }
          final message = _messages[index];
          return _bubble(
            message.role,
            message.content,
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
    final format = await showCupertinoModalPopup<MessageCopyFormat>(
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
    String? providerName,
    String? providerPresetId,
    String? modelId,
    int? firstTokenMs,
    int? totalMs,
    ReplyUsage? usage,
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
                maxWidth: MediaQuery.sizeOf(context).width * .86,
              ),
              child: Column(
                crossAxisAlignment: user
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
                    decoration: BoxDecoration(
                      color: user ? IosColors.userBubble : IosColors.assistant,
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
                            ),
                          ),
                      ],
                    ),
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
                      onSpeak: user ? null : () => _playSpeech(content),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_transcribing)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  const CupertinoActivityIndicator(radius: 8),
                  const SizedBox(width: 8),
                  Text(
                    tr('正在识别语音…'),
                    style: TextStyle(color: IosColors.secondary, fontSize: 13),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(46, 44),
                onPressed: _toggleVoiceMode,
                child: Icon(
                  _voiceMode ? CupertinoIcons.keyboard : CupertinoIcons.mic,
                  color: IosColors.blue,
                  size: 27,
                  semanticLabel: tr(_voiceMode ? '切换到文字输入' : '切换到语音输入'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _voiceMode
                    ? Semantics(
                        button: true,
                        label: tr('按住说话，松开识别'),
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _voiceDown,
                          onPointerMove: _voiceMove,
                          onPointerUp: (_) => _voiceUp(),
                          onPointerCancel: (_) => _voiceCancel(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _voicePointerDown
                                  ? IosColors.blue.withValues(alpha: .22)
                                  : IosColors.assistant,
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(color: IosColors.separator),
                            ),
                            child: Text(
                              tr('按住说话'),
                              style: TextStyle(
                                color: IosColors.label,
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
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        textCapitalization: TextCapitalization.sentences,
                        placeholder: _providers.isEmpty
                            ? tr('先接入模型服务')
                            : tr('发送消息'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: IosColors.surface,
                          borderRadius: BorderRadius.circular(21),
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
                      : (_starting || _recording || _transcribing
                            ? null
                            : _send),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _sending
                          ? IosColors.destructive
                          : _starting
                          ? IosColors.secondary
                          : IosColors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _sending
                          ? CupertinoIcons.stop_fill
                          : CupertinoIcons.arrow_up,
                      color: IosColors.onAccent,
                      size: 21,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}
