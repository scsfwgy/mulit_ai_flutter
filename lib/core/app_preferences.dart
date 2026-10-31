import 'package:mulit_ai_flutter/agent/agent_context.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/i18n/app_language.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/voice/voice_selection.dart';

// 语言枚举与文案表已迁至 lib/i18n/；此处保留导出以兼容既有导入路径。
export 'package:mulit_ai_flutter/i18n/app_language.dart'
    show AppLanguage, languageSelfName;

enum AppAppearance { system, light, dark }

enum ChatInfoField {
  modelId('i18n.model_id'),
  firstFrame('i18n.time_to_first_text'),
  totalTime('i18n.total_time'),
  tokens('i18n.token_usage'),
  characters('i18n.characters'),
  copy('i18n.copy_button'),
  speech('i18n.speech_button');

  const ChatInfoField(this.label);
  final String label;
}

enum AppSkin {
  blue('blue', 'i18n.classic_blue', Color(0xFF007AFF)),
  teal('teal', 'i18n.teal', Color(0xFF008C83)),
  wechat('wechat', 'i18n.wechat_green', Color(0xFF07C160)),
  violet('violet', 'i18n.violet', Color(0xFF7654D6));

  const AppSkin(this.value, this.label, this.accent);
  final String value;
  final String label;
  final Color accent;
}

class AppPreferences extends ChangeNotifier with WidgetsBindingObserver {
  AppPreferences._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = AppPreferences._();
  static const _companion = MethodChannel('between_models/companion_install');

  bool autoReadReplies = false;
  bool agentEnabled = false;
  bool simpleMessageInfo = false;
  int contextWindowTokens = ChatContext.defaultWindowTokens;
  int agentContextWindowTokens = ChatContext.defaultWindowTokens;

  AppLanguage _language = AppLanguage.zh;

  /// 界面语言；赋值时同步生效到文案表，无需等待持久化完成。
  AppLanguage get language => _language;
  set language(AppLanguage value) {
    _language = value;
    I18n.apply(value);
  }

  AppSkin skin = AppSkin.blue;
  AppAppearance appearance = AppAppearance.system;
  final Map<ChatInfoField, bool> _chatInfoVisible = {
    for (final field in ChatInfoField.values) field: true,
  };

  bool showChatInfo(ChatInfoField field) =>
      !simpleMessageInfo && (_chatInfoVisible[field] ?? true);

  bool get dark => switch (appearance) {
    AppAppearance.light => false,
    AppAppearance.dark => true,
    AppAppearance.system =>
      PlatformDispatcher.instance.platformBrightness == Brightness.dark,
  };

  ThemeMode get themeMode => switch (appearance) {
    AppAppearance.system => ThemeMode.system,
    AppAppearance.light => ThemeMode.light,
    AppAppearance.dark => ThemeMode.dark,
  };

  @override
  void didChangePlatformBrightness() {
    _syncSystemBars();
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (language != AppLanguage.system) return;
    notifyListeners();
    unawaited(_syncWatchLanguage());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncWatchLanguage());
  }

  Future<void> _syncWatchLanguage() async {
    if (!supportsWatchCompanion) return;
    try {
      await _companion.invokeMethod<void>('syncPreferences', {
        'language': english ? 'en' : 'zh',
      });
    } on MissingPluginException {
      // Desktop, tests, and older phone builds may not expose this channel.
    } on PlatformException {
      // Retry on the next foreground entry; phone language remains saved.
    }
  }

  void _syncSystemBars() => SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: dark ? Colors.black : const Color(0xFFF2F2F7),
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  /// 当前实际生效的语言是否为英文（跟随系统时按系统区域解析）。
  bool get english => I18n.current == AppLanguage.en;

  /// 界面 locale。
  ///
  /// 繁体必须带上 `Hant` 脚本标签：`MaterialApp.supportedLocales` 的解析算法
  /// 在只有 `zh` 时会把 `zh-Hant-TW` 归一到 `zh`，框架内置控件（复制、取消等）
  /// 会退回简体。
  Locale? get locale => switch (language) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.zhTW => traditionalChinese,
    AppLanguage.en => const Locale('en'),
  };

  /// 繁体中文（台湾）locale。手表只支持简体和英文，与此无关。
  static const traditionalChinese = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
    countryCode: 'TW',
  );

  /// 繁体中文（香港）locale：平台直接上报 `zh-HK` 时按繁体解析。
  static const traditionalChineseHongKong = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
    countryCode: 'HK',
  );

  /// 繁体中文（澳门）locale：平台上报 `zh-MO` 时按繁体解析。
  ///
  /// 必须带 `Hant`。框架的 `getMaterialTranslation` 对语言为 `zh` 且无脚本
  /// 标签的 locale 只在国家是 HK/TW 时返回繁体，`zh-MO` 会落到简体（内置复制
  /// 按钮显示「复制」）。而 `basicLocaleListResolution` 的「语言 + 国家」匹配
  /// 只比较 `languageCode` 与 `countryCode`，所以登记带脚本的 `zh_Hant_MO`
  /// 就能同时命中 `zh-MO` 与 `zh-Hant-MO`，无需再登记裸 `Locale('zh','MO')`
  /// （后者反而会被框架解析成简体）。
  static const traditionalChineseMacao = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
    countryCode: 'MO',
  );

  /// `MaterialApp.supportedLocales`。
  ///
  /// 顺序即 `basicLocaleListResolution` 的回退顺序，`Locale('zh')` 保持在首位
  /// 以沿用「平台未上报语言时默认简体」的历史行为。三个繁体 locale 分别覆盖
  /// 台/港/澳，缺任意一个都会让对应地区的系统语言回退到简体框架控件，与应用
  /// 自身的繁体文案不一致。
  static const supportedLocales = <Locale>[
    Locale('zh'),
    traditionalChinese,
    traditionalChineseHongKong,
    traditionalChineseMacao,
    Locale('en'),
  ];

  /// 读取语言偏好并载入文案表。
  ///
  /// 必须在 `runApp` 之前完成，否则启动页会先渲染出裸 key；手表后台 engine
  /// 也必须在 `ready` 之前调用——后台是独立的 FlutterEngine，前台的静态文案
  /// 表不会共享过去。
  ///
  /// 不抛异常：数据库暂不可用时按默认语言载入文案表，界面语言回退简体中文，
  /// 聊天页随后显示存储错误。
  Future<void> loadLocalization() async {
    var saved = AppLanguage.zh;
    try {
      final raw = await ChatStore.instance.setting('app_language');
      // 未设置过语言时默认简体中文，与历史行为一致。
      if (raw != null) saved = AppLanguage.fromCode(raw);
    } catch (_) {
      // 数据库不可用：文案表仍会载入，只是语言停在默认值。
    }
    language = saved;
    await I18n.load(saved);
  }

  Future<void> load() async {
    await loadLocalization();
    await initializeSystemVoiceDefaults(ChatStore.instance);
    agentEnabled = await ChatStore.instance.setting('agent_enabled') == '1';
    contextWindowTokens = ChatContext.parseWindow(
      await ChatStore.instance.setting(ChatContext.settingKey),
    );
    agentContextWindowTokens = ChatContext.parseWindow(
      await ChatStore.instance.setting(AgentContext.settingKey),
    );
    simpleMessageInfo =
        await ChatStore.instance.setting('chat_info_simple') == '1';
    autoReadReplies =
        await ChatStore.instance.setting('voice_auto_read') == '1';
    final savedSkin = await ChatStore.instance.setting('app_skin');
    final savedAppearance = await ChatStore.instance.setting('app_appearance');
    skin = AppSkin.values.firstWhere(
      (item) => item.value == savedSkin,
      orElse: () => AppSkin.blue,
    );
    appearance = AppAppearance.values.firstWhere(
      (item) => item.name == savedAppearance,
      orElse: () => AppAppearance.system,
    );
    for (final field in ChatInfoField.values) {
      _chatInfoVisible[field] =
          await ChatStore.instance.setting('chat_info_${field.name}') != '0';
    }
    _syncSystemBars();
    notifyListeners();
    unawaited(_syncWatchLanguage());
  }

  Future<void> setSimpleMessageInfo(bool value) async {
    await ChatStore.instance.saveSetting('chat_info_simple', value ? '1' : '0');
    simpleMessageInfo = value;
    notifyListeners();
  }

  Future<void> setAgentEnabled(bool value) async {
    await ChatStore.instance.saveSetting('agent_enabled', value ? '1' : '0');
    agentEnabled = value;
    notifyListeners();
  }

  Future<void> setContextWindowTokens(int value) async {
    if (!ChatContext.windowOptions.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    await ChatStore.instance.saveSetting(ChatContext.settingKey, '$value');
    contextWindowTokens = value;
    notifyListeners();
  }

  Future<void> setAgentContextWindowTokens(int value) async {
    if (!ChatContext.windowOptions.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    await ChatStore.instance.saveSetting(AgentContext.settingKey, '$value');
    agentContextWindowTokens = value;
    notifyListeners();
  }

  Future<void> setAutoReadReplies(bool value) async {
    await ChatStore.instance.saveSetting('voice_auto_read', value ? '1' : '0');
    autoReadReplies = value;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage value) async {
    await ChatStore.instance.saveSetting('app_language', value.code);
    language = value;
    notifyListeners();
    unawaited(_syncWatchLanguage());
  }

  Future<void> setSkin(AppSkin value) async {
    await ChatStore.instance.saveSetting('app_skin', value.value);
    skin = value;
    notifyListeners();
  }

  Future<void> setAppearance(AppAppearance value) async {
    await ChatStore.instance.saveSetting('app_appearance', value.name);
    appearance = value;
    _syncSystemBars();
    notifyListeners();
  }

  Future<void> setChatInfoVisible(ChatInfoField field, bool visible) async {
    await ChatStore.instance.saveSetting(
      'chat_info_${field.name}',
      visible ? '1' : '0',
    );
    _chatInfoVisible[field] = visible;
    notifyListeners();
  }
}
