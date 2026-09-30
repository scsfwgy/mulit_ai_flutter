import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';

enum AppLanguage { system, zh, en }

enum AppAppearance { system, light, dark }

enum ChatInfoField {
  modelId('模型 ID'),
  firstFrame('首帧耗时'),
  totalTime('总耗时'),
  tokens('Token 用量'),
  characters('字数');

  const ChatInfoField(this.label);
  final String label;
}

enum AppSkin {
  blue('blue', '经典蓝', Color(0xFF007AFF)),
  teal('teal', '海蓝绿', Color(0xFF008C83)),
  violet('violet', '紫罗兰', Color(0xFF7654D6));

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

  AppLanguage language = AppLanguage.zh;
  AppSkin skin = AppSkin.blue;
  AppAppearance appearance = AppAppearance.system;
  final Map<ChatInfoField, bool> _chatInfoVisible = {
    for (final field in ChatInfoField.values) field: true,
  };

  bool showChatInfo(ChatInfoField field) => _chatInfoVisible[field] ?? true;

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

  bool get english => switch (language) {
    AppLanguage.en => true,
    AppLanguage.zh => false,
    AppLanguage.system =>
      PlatformDispatcher.instance.locale.languageCode.toLowerCase() == 'en',
  };

  Locale? get locale => switch (language) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.en => const Locale('en'),
  };

  Future<void> load() async {
    final savedLanguage = await ChatStore.instance.setting('app_language');
    final savedSkin = await ChatStore.instance.setting('app_skin');
    final savedAppearance = await ChatStore.instance.setting('app_appearance');
    language = AppLanguage.values.firstWhere(
      (item) => item.name == savedLanguage,
      orElse: () => AppLanguage.zh,
    );
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

  Future<void> setLanguage(AppLanguage value) async {
    await ChatStore.instance.saveSetting('app_language', value.name);
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

String tr(String chinese) {
  if (!AppPreferences.instance.english) return chinese;
  final direct = _english[chinese];
  if (direct != null) return direct;
  final voiceHttp = RegExp(r'^语音服务请求失败（HTTP (\d+)）').firstMatch(chinese);
  if (voiceHttp != null) {
    return 'Voice service failed (HTTP ${voiceHttp.group(1)}). Check the key, model and permissions';
  }
  final voiceCatalogHttp = RegExp(r'^获取模型列表失败（HTTP (\d+)）$')
      .firstMatch(chinese);
  if (voiceCatalogHttp != null) {
    return 'Could not fetch models (HTTP ${voiceCatalogHttp.group(1)})';
  }
  final doubaoCode = RegExp(r'^豆包语音(识别|合成)失败（状态码 ([^）]+)）').firstMatch(chinese);
  if (doubaoCode != null) {
    final action = doubaoCode.group(1) == '识别' ? 'transcription' : 'speech';
    return 'Doubao $action failed (status ${doubaoCode.group(2)}). Check resource permissions';
  }
  for (final (prefix, translated) in _englishPrefixes) {
    if (chinese.startsWith(prefix)) {
      return '$translated${chinese.substring(prefix.length)}';
    }
  }
  return chinese;
}

const _englishPrefixes = <(String, String)>[
  ('发送失败：', 'Send failed: '),
  ('重试失败：', 'Retry failed: '),
  ('无法打开本地数据：', 'Could not open local data: '),
  ('网络连接失败：', 'Network connection failed: '),
  ('服务错误：', 'Service error: '),
  ('请求失败 (', 'Request failed ('),
  ('获取模型失败 (', 'Model fetch failed ('),
  ('获取模型列表失败：', 'Could not fetch models: '),
];

const _english = <String, String>{
  '手表': 'Watch',
  '手表数据': 'Watch data',
  'Wear OS 会加密保存所选服务密钥与离线问答，并在重连后同步到手机。Apple Watch 首版只保存最近显示的问答，语音和模型请求由配对 iPhone 处理，不接收 API Key。清空手机数据不会自动清除手表数据。': 'Wear OS stores selected service keys encrypted and keeps offline chats for later phone sync. The first Apple Watch version stores only recent displayed turns; the paired iPhone handles voice and model requests, and no API key is sent to Apple Watch. Clearing phone data does not automatically erase watch data.',
  '手机上的话题、聊天记录、服务配置、API Key 和提示词会被删除。Wear OS 上已同步的配置和离线问答、Apple Watch 上最近显示的问答不会自动清除，需分别在手表上卸载应用。此操作无法撤销。': 'Chats, service settings, API keys and prompts on the phone will be deleted. Synced settings and offline chats on Wear OS and recent displayed turns on Apple Watch remain until you uninstall the respective watch app. This cannot be undone.',
  '手表使用的模型': 'Watch model',
  '手表播报回复': 'Speak replies on watch',
  '配套手表应用': 'Watch companion app',
  '尚未配对 Apple Watch': 'No Apple Watch paired',
  'Apple Watch 尚未安装 AI Link': 'AI Link is not installed on Apple Watch',
  'Apple Watch 已连接': 'Apple Watch connected',
  '手表应用已安装，等待连接': 'Watch app installed; waiting for connection',
  '在 iPhone 的 Watch 应用中安装 AI Link 手表版。首次使用请先在手机端配置文字和语音服务；手表与手机配对并连接后，点上方状态重新检查。': 'Install AI Link for Apple Watch in the Watch app on iPhone. Configure text and voice services on iPhone first, then tap the status above after pairing and connecting.',
  'Apple Watch 首版由配对 iPhone 完成语音识别、模型请求和可选朗读，结果保存到手机会话。手表仅保存最近显示的问答，不接收 API Key；手机不可达时暂不能提问。': 'The first Apple Watch version uses the paired iPhone for transcription, model requests and optional speech. Replies are saved in iPhone chats. The watch keeps only recent displayed turns and receives no API keys; questions require the iPhone to be reachable.',
  '手表应用安装': 'Install watch app',
  '手表端尚未安装': 'Watch app is not installed',
  '检测到已连接的 Wear OS 手表。安装手表应用后，可在手表上语音提问。': 'A Wear OS watch is connected. Install the watch app to ask questions by voice.',
  '去安装': 'Install now',
  '稍后': 'Later',
  '在手表安装': 'Install on watch',
  '正在检查已连接的手表…': 'Checking connected watches…',
  '尚未建立 Wear OS 数据连接': 'Wear OS data connection is not established',
  '有手表尚未安装应用': 'A connected watch needs the app',
  '已连接的手表均已安装应用': 'App installed on all connected watches',
  '无法检查手表连接': 'Could not check watch connection',
  '无法检查手表数据连接，请稍后重试':
      'Could not check the watch data connection. Try again later.',
  '此设备不支持手表安装引导': 'Watch installation guidance is unavailable on this device',
  '无法在手表打开安装页': 'Could not open the installation page on the watch',
  '无法在手表打开安装页，请检查连接或手动安装': 'Could not open the installation page on the watch. Check the connection or install it manually.',
  '已请求在手表打开安装页。若商店没有此应用，请从原安装渠道获取手表版。': 'Requested the installation page on the watch. If the store does not list this app, get the watch version from your original installation source.',
  '蓝牙配对后，还需完成 Wear OS 配套应用的连接设置。模拟器请使用 Android Studio 的 Pair Wearable；完成后点上方状态重新检查。商店暂无本应用时，请从原安装渠道获取手表版。': 'After Bluetooth pairing, finish connecting through the Wear OS companion app. For emulators, use Pair Wearable in Android Studio, then tap the status above to check again. If the store does not list this app, use your original installation source.',
  '请先配置模型服务': 'Configure a model provider first',
  '已连接手机时优先使用手机网络，失败后尝试手表网络；未连接时先用手表 Wi-Fi 或蜂窝网络。仅明确的网络故障才自动换路，避免重复请求。配置与密钥由手机同步到手表。': 'Use the phone network first when connected, then try the watch network if it fails. Otherwise use watch Wi-Fi or cellular first. Only clear network failures trigger a switch to avoid duplicate requests. Settings and keys sync from the phone.',
  '请先在语音服务中选择识别服务；开启播报时还需要选择朗读服务。手表问答保存在手机会话列表中。': 'Choose a transcription service in Voice services. Speaking also needs a speech service. Watch chats appear in the phone conversation list.',
  '在语音服务中选择识别服务，并设置转写后是否自动发送；该开关同时适用于手机和手表。开启播报时还需选择朗读服务。': 'Choose a transcription service and automatic sending in Voice services. The sending switch applies to phone and watch. Speaking also needs a speech service.',
  'OpenAI 兼容音频': 'OpenAI-compatible audio',
  '小米 MiMo': 'Xiaomi MiMo',
  '豆包语音': 'Doubao Speech',
  '没有识别到可用文字，请重试': 'No usable speech was detected. Try again',
  '识别文字过长，请分段录音': 'Transcript too long. Record shorter segments',
  '语音服务返回内容过大': 'Voice service response is too large',
  '语音服务返回格式无效': 'Invalid voice service response',
  '录音为空或超过 12 MB，请缩短录音':
      'Recording is empty or over 12 MB. Record a shorter clip',
  '语音服务缺少 API Key': 'Voice service API key is missing',
  '没有可朗读的文字': 'No text to read aloud',
  '消息过长，请选择较短的内容朗读': 'Message too long. Choose shorter text to read aloud',
  '语音服务没有返回音频': 'Voice service returned no audio',
  '语音服务返回的音频无效': 'Voice service returned invalid audio',
  '录音文件不存在，请重试': 'Recording file is missing. Try again',
  '请先选择语音识别服务': 'Choose a transcription service first',
  '请填写服务名称、模型 ID 与音色': 'Enter a service name, model IDs and voice ID',
  '小米 MiMo 请使用官方接口地址': 'Use the official Xiaomi MiMo API address',
  '豆包语音请使用官方接口地址': 'Use the official Doubao Speech API address',
  '请填写语音服务 API Key': 'Enter the voice service API key',
  '选中的文字服务缺少 API Key': 'The selected text provider has no API key',
  '语音服务': 'Voice services',
  '语音识别服务': 'Transcription service',
  '语音朗读服务': 'Speech service',
  '回复完成后自动朗读': 'Read replies aloud automatically',
  '语音提供商': 'Voice providers',
  '添加语音提供商': 'Add voice provider',
  '编辑语音提供商': 'Edit voice provider',
  '删除语音提供商': 'Delete voice provider',
  '删除语音提供商？': 'Delete voice provider?',
  '语音模型': 'Voice models',
  '识别模型 ID / 资源 ID': 'ASR model / resource ID',
  '合成模型 ID / 资源 ID': 'TTS model / resource ID',
  '音色 ID': 'Voice ID',
  '选择音色': 'Choose voice',
  '默认': 'Default',
  '中文女声': 'Chinese female voice',
  '中文男声': 'Chinese male voice',
  '英文女声': 'English female voice',
  '英文男声': 'English male voice',
  '录音识别极速版': 'Fast transcription',
  '语音合成 2.0': 'Speech synthesis 2.0',
  '甜美桃子': 'Sweet Peach',
  '大壹': 'Da Yi',
  '黑猫侦探社咪仔': 'Mizai',
  '鸡汤女': 'Warm Narrator',
  '魅力女友': 'Charming Girlfriend',
  '流畅女声': 'Fluent Female Voice',
  '儒雅逸辰': 'Yichen',
  '手动输入 ID': 'Enter an ID manually',
  '输入模型或音色 ID': 'Enter a model or voice ID',
  '使用此 ID': 'Use this ID',
  '选择': 'Choose',
  '搜索 ID 或名称': 'Search ID or name',
  '服务端返回': 'Returned by server',
  '官方示例': 'Official examples',
  '模型列表仅包含服务端返回的 ID，语音接口和账号权限仍需实际验证。': 'The server returned these IDs. Audio endpoints and account access still need testing.',
  '此服务没有可用的 API Key 列表接口。示例不代表账号已开通；也可返回手动填写。': 'No API-key catalog is available for this service. Examples do not confirm access; you can also enter an ID manually.',
  '示例来自官方文档，不代表当前账号已开通；也可返回手动填写。': 'Examples come from official docs and do not confirm account access. You can also enter an ID manually.',
  '模型列表过大': 'Model list is too large',
  '服务未提供模型列表': 'The service has no model list',
  '无法获取模型列表，请检查网络或手动填写':
      'Could not fetch models. Check the network or enter an ID manually',
  '密钥来源': 'Key source',
  '独立密钥': 'Separate key',
  '复用文字服务': 'Reuse text provider',
  '文字服务已删除': 'Text provider was deleted',
  '不使用': 'None',
  '未设置': 'Not set',
  '朗读回复': 'Read reply aloud',
  '语音输入': 'Voice input',
  '切换到语音输入': 'Switch to voice input',
  '切换到文字输入': 'Switch to text input',
  '按住说话': 'Hold to talk',
  '正在录音': 'Recording',
  '松开取消': 'Release to cancel',
  '松开转写 · 上滑取消': 'Release to transcribe · slide up to cancel',
  '按住说话，松开识别': 'Hold to speak, release to transcribe',
  '松开结束录音 · 上滑取消': 'Release to transcribe · slide up to cancel',
  '松开取消录音': 'Release to cancel recording',
  '转写后自动发送': 'Send automatically after transcription',
  '结束录音并识别': 'Stop and transcribe',
  '录音中': 'Recording',
  '正在识别语音…': 'Transcribing…',
  '取消录音': 'Cancel recording',
  '识别完成，请检查文字后发送': 'Review the transcript, then send',
  '按住录音，松开后转写。转写后是否直接发送同时适用于手机和手表；朗读声音由 AI 生成。': 'Hold to record and release to transcribe. Automatic sending applies to both phone and watch; spoken replies are AI-generated.',
  '请允许麦克风权限后重试': 'Allow microphone access and try again',
  '无法开始录音，请检查麦克风权限': 'Could not record. Check microphone access',
  '语音识别失败，请重试': 'Transcription failed. Try again',
  '语音朗读失败，请重试': 'Could not read aloud. Try again',
  '请检查配置后重试': 'Check the configuration and try again',
  'API Key（留空保留原密钥）': 'API key (blank keeps current key)',
  '录音只发送给选定的语音识别服务；识别文字先填入输入框供你检查。朗读声音由 AI 生成，应用只播放返回的音频。': 'Recordings go directly to your chosen transcription service. Review the text before sending. Spoken replies are AI-generated; the app only plays the returned audio.',
  '文字服务密钥仅在接口确实支持语音时可复用。豆包语音须单独填写豆包语音控制台的 API Key。': 'Reuse a text key only when its API supports audio. Doubao Speech needs its own API key.',
  '模型与音色 ID 需要在对应服务开通。豆包语音的模型栏填写资源 ID。': 'Model and voice IDs must be available on the service. Use resource IDs for Doubao Speech.',
  'AI Link': 'AI Link',
  '更多': 'More',
  '对话列表': 'Chats',
  '新对话': 'New chat',
  '切换模型': 'Switch model',
  '模型服务': 'Model services',
  '设置': 'Settings',
  '联系与反馈': 'Contact and feedback',
  '邮箱已复制': 'Email address copied',
  '取消': 'Cancel',
  '选择模型': 'Choose model',
  '模型列表': 'Models',
  '其他模型': 'Other models',
  '没有匹配的模型': 'No matching models',
  '搜索模型 ID': 'Search model ID',
  '接入模型服务': 'Add a model service',
  '开始新对话': 'Start a new chat',
  '一个地方，和不同模型继续对话。': 'Keep every model conversation in one place.',
  '输入消息，开始讨论。': 'Type a message to begin.',
  '请先停止当前回复，再切换模型': 'Stop the current response before switching models',
  '无法打开这个链接': 'Unable to open this link',
  '检查密钥': 'Check key',
  '检查服务配置': 'Check service settings',
  '重试回复': 'Retry response',
  '外观': 'Appearance',
  '主题色': 'Accent color',
  '换肤': 'Appearance',
  '模式': 'Mode',
  '白天': 'Light',
  '黑夜': 'Dark',
  '模型设置': 'Model settings',
  '消息信息': 'Message details',
  '首帧耗时': 'Time to first text',
  '首帧': 'First text',
  '总耗时': 'Total time',
  '耗时': 'Time',
  '加载中': 'Loading',
  'Token 用量': 'Token usage',
  '输入': 'Input',
  '输出': 'Output',
  '字数': 'Characters',
  '字': 'chars',
  '用户消息显示模型与字数；耗时和 Token 属于整次回复请求。旧消息缺少的统计不显示；服务未提供用量时显示 Token —。': 'Your messages show the model and character count. Timing and tokens cover the whole reply request. Missing statistics in old messages stay hidden; providers without usage data show Token —.',
  '复制消息': 'Copy message',
  '复制 Markdown 原文': 'Copy Markdown source',
  '复制格式化文本': 'Copy formatted text',
  '复制失败': 'Could not copy',
  '首轮回复后，会额外请求当前模型生成会话标题，可能产生少量用量。': 'After the first reply, the current model receives one extra short request to name the chat. This may use a few tokens.',
  '语言': 'Language',
  '跟随系统': 'Follow system',
  '简体中文': 'Simplified Chinese',
  '关于': 'About',
  '版本': 'Version',
  '应用信息': 'App information',
  '数据与隐私': 'Data & privacy',
  '完整隐私政策': 'Full privacy policy',
  '官方网站': 'Official website',
  '提示词': 'Prompts',
  '全局和单模型提示词': 'Global and model prompts',
  '服务与数据': 'Services & data',
  '经典蓝': 'Classic blue',
  '海蓝绿': 'Teal',
  '紫罗兰': 'Violet',
  '开源许可': 'Open source licenses',
  '我的服务': 'My services',
  '对话设置': 'Chat settings',
  '隐私与数据': 'Privacy & data',
  '国内服务': 'China providers',
  '国际服务': 'International providers',
  '聚合与推理平台': 'Aggregators & inference',
  '自定义 API / JSON 导入': 'Custom API / JSON import',
  '扫码导入配置': 'Scan to import',
  '扫描完整配置 JSON 二维码': 'Scan a full JSON configuration QR code',
  '查看存储方式与清空本地数据': 'Review storage and clear local data',
  '最近': 'Recent',
  '最近使用': 'Recently used',
  '模型 ID': 'Model ID',
  '手动输入模型 ID': 'Enter a model ID',
  '从服务端获取模型列表': 'Fetch models from server',
  '查看模型列表': 'View model list',
  '优先显示本地缓存，可在列表中刷新。获取失败时仍可手动填写模型 ID。': 'Shows the local cache first. Refresh in the list, or enter a model ID if fetching fails.',
  '服务端模型': 'Server models',
  '使用此模型': 'Use this model',
  '选择服务': 'Choose service',
  '服务名称': 'Service name',
  '接口协议': 'API protocol',
  'API 根地址': 'API base URL',
  '默认模型': 'Default model',
  '模型': 'Models',
  '连接设置': 'Connection',
  '编辑服务配置': 'Edit service',
  '保存并接入': 'Save and connect',
  '保存': 'Save',
  '删除服务': 'Delete service',
  '扫码填写 API Key': 'Scan API key',
  '扫码填写密钥': 'Scan key',
  '粘贴密钥': 'Paste key',
  '留空则保留原密钥': 'Leave blank to keep current key',
  '表单': 'Form',
  '完整配置 JSON': 'Full JSON configuration',
  '全局提示词': 'Global prompt',
  '模型提示词': 'Model prompts',
  '单模型': 'Per model',
  '新增模型提示词': 'Add model prompt',
  '适用模型': 'Applies to',
  '系统提示词': 'System prompt',
  '保存提示词': 'Save prompt',
  '尚未设置': 'Not set',
  '话题名称': 'Chat title',
  '重命名话题': 'Rename chat',
  '重命名': 'Rename',
  '删除话题': 'Delete chat',
  '还没有对话': 'No chats yet',
  '开始新的对话': 'Start a new chat',
  '数据存放': 'Storage',
  '聊天与配置': 'Chats & settings',
  '模型请求': 'Model requests',
  '本地数据管理': 'Local data',
  '单独删除': 'Delete individually',
  '清空所有本地数据': 'Clear all local data',
  '清空本地数据？': 'Clear local data?',
  '清空': 'Clear',
  '请稍候…': 'Please wait…',
  '正在清空…': 'Clearing…',
  '正在保存…': 'Saving…',
  '配置有误': 'Invalid configuration',
  '无法导入': 'Unable to import',
  '无法保存': 'Unable to save',
  '已复制': 'Copied',
  '好': 'OK',
  '请选择': 'Choose',
  '删除': 'Delete',
  '编辑配置': 'Edit configuration',
  '继续扫码': 'Scan again',
  '扫码导入服务': 'Scan service',
  '模型服务已删除': 'Model service deleted',
  '服务已删除': 'Service deleted',
  'OpenAI 兼容': 'OpenAI compatible',
  '先接入模型服务': 'Add a model service first',
  '发送消息': 'Message',
  '删除服务配置？': 'Delete service?',
  '删除模型提示词？': 'Delete model prompt?',
  '写下模型应遵循的规则、角色或输出格式':
      'Describe the rules, role, or output format for this model',
  '请先停止生成': 'Stop the response first',
  '停止当前回复后即可删除这个话题。': 'Stop the current response before deleting this chat.',
  '删除这个话题？': 'Delete this chat?',
  '本地聊天记录会一并删除，无法恢复。':
      'Its local messages will be deleted and cannot be recovered.',
  '正在获取模型列表…': 'Fetching models…',
  '刷新': 'Refresh',
  '刷新模型列表': 'Refresh model list',
  '刷新失败，已保留当前列表。': 'Refresh failed. The current list is still available.',
  '输入模型 ID': 'Enter model ID',
  '例如：我的 OpenAI': 'For example: My OpenAI',
  '新建模型服务': 'Add model service',
  '扫一扫': 'Scan',
  '密钥保存在手机安全存储中；选作 Wear OS 服务时会经配对通道同步并加密保存。Apple Watch 首版由 iPhone 代为请求，不接收密钥。我们不设中转服务器，请求会直达你配置的 API 服务商。': 'Keys stay in secure phone storage. Selected Wear OS services sync keys over the paired connection and store them encrypted. The first Apple Watch version sends requests through iPhone and receives no keys. We run no relay server; requests go directly to your configured API provider.',
  '还没有接入服务。选择下方平台，填写密钥即可开始。':
      'No services yet. Choose a provider below and enter your key.',
  '已填入 API 地址和示例模型；账号可用模型以服务端为准。': 'API URLs and example models are prefilled. Available models depend on your account.',
  '在所有模型的每次请求中生效。': 'Applied to every model request.',
  '按服务和模型 ID 区分；发送时接在全局提示词之后。留空的模型只使用全局提示词。': 'Set per service and model ID. It follows the global prompt. Models without one use only the global prompt.',
  '接入模型服务后，即可为指定模型设置提示词。':
      'Add a model service to set prompts for individual models.',
  '仅对上方服务与模型 ID 的请求生效，不会显示在聊天记录中。': 'Applied only to this service and model ID. It does not appear in chat history.',
  '清空并保存即可关闭全局提示词。': 'Clear and save to disable the global prompt.',
  '已保存的服务和模型 ID 固定；需要更换时请新增一条。': 'The saved service and model ID are fixed. Add a new entry to change them.',
  '可以使用未出现在服务端列表中的模型。':
      'You can use a model that is missing from the server list.',
  '获取失败时仍可手动填写模型 ID。密钥不会写入聊天数据库。': 'You can enter a model ID if fetching fails. The key is never stored in the chat database.',
  '填写 API 根地址，应用会自动拼接 /chat/completions 或 /messages。':
      'Enter the API base URL. The app appends /chat/completions or /messages.',
  '扫描仅包含 API Key 字符串的二维码，识别后自动填入。':
      'Scan a QR code containing only the API key to fill it in.',
  '扫描包含完整服务配置 JSON 的二维码，识别成功后自动导入。': 'Scan a QR code containing a full service configuration JSON to import it.',
  '话题、消息、提示词和非密钥配置保存在本机数据库中，数据库内容未加密。': 'Chats, messages, prompts, and settings are stored in an unencrypted local database.',
  '保存在设备的安全存储中，不写入聊天数据库。':
      'Stored in the device secure storage, never in the chat database.',
  '对话内容、提示词和 API Key 从设备直接发送到你选择的服务地址，由该服务处理。': 'Chats, prompts, and API keys go directly from your device to the chosen service.',
  '清空后无法在应用内恢复聊天记录。已经发送给第三方模型服务的内容不受此操作影响。': 'Cleared chats cannot be recovered in the app. Data already sent to a provider is unaffected.',
  '可在话题列表删除某个话题，在模型服务页删除某项服务及其密钥。': 'Delete individual chats in Chats, or a service and its key in Model services.',
  '所有话题、聊天记录、服务配置、API Key 和提示词都会从本应用中删除。此操作无法撤销。': 'All chats, service settings, API keys, and prompts will be deleted from this app. This cannot be undone.',
  '请先停止正在生成的回复，再清空数据。': 'Stop the current response before clearing data.',
  '请先停止回复或等待标题生成完成，再清空数据。': 'Stop the reply or wait for the chat title to finish before clearing data.',
  '本地保存': 'Stored locally',
  '话题和消息保存在设备的 SQLite 数据库中。API Key 保存在系统安全存储中。': 'Chats and messages are stored in SQLite on this device. API keys are stored in secure storage.',
  '请求直连': 'Direct requests',
  '请求从设备直接发送到你配置的模型服务商。': 'Requests go directly from your device to the model service you configure.',
  '按模型 ID 的服务或家族前缀分组；搜索可查找全部模型。':
      'Grouped by service or model family. Search covers every model.',
  '仅显示前 100 个结果，可搜索更多模型。': 'Showing the first 100 results. Search for more.',
  '本组仅显示前 100 个模型，可搜索更多。':
      'Showing the first 100 in this group. Search for more.',
  '对话': 'Chats',
  '其他': 'Other',
  '名称和模型不能为空': 'Service name and model cannot be empty',
  '字段：name、protocol、baseUrl、model、apiKey。编辑时 apiKey 留空表示保留原密钥；JSON 编辑框会明文显示新填入的密钥。': 'Fields: name, protocol, baseUrl, model, apiKey. Leave apiKey blank when editing to keep the current key. A newly entered key is visible in the JSON editor.',
  '支持 OpenAI 兼容 Chat Completions 与 Claude Messages 协议。':
      'Supports OpenAI compatible Chat Completions and Claude Messages.',
  '服务没有返回可用模型': 'The service returned no usable models',
  '请先修正配置 JSON，再扫码填写密钥': 'Fix the configuration JSON before scanning a key',
  '请先填写 API Key': 'Enter an API key first',
  '复用密钥时，API 根地址须与文字服务一致':
      'When reusing a key, the API base URL must match the text provider',
  '请先填写有效的配置 JSON': 'Enter valid configuration JSON',
  '请填写 API Key': 'Enter an API key',
  '服务配置已删除，请重新选择模型。': 'The service was deleted. Choose a model again.',
  '此服务尚未配置 API Key。': 'This service has no API key.',
  '此话题原来的服务已删除，请重新选择模型。':
      'The service for this chat was deleted. Choose a model again.',
  '请先在服务设置中填写 API Key': 'Enter an API key in service settings first',
  '服务没有返回可用模型，可手动输入模型 ID。':
      'The service returned no usable models. You can enter a model ID.',
  '请输入模型 ID': 'Enter a model ID',
  '全局': 'Global',
  '已删除的服务': 'Deleted service',
  '模型 ID 可以手动填写，例如当前服务的默认模型。': 'You can enter a model ID manually, such as this service’s default model.',
  '请选择服务，并填写模型 ID 和提示词': 'Choose a service, then enter a model ID and prompt',
  '清理未完成，请重试。': 'Could not finish clearing data. Try again.',
  'API 地址必须使用 HTTPS；模拟器本机地址可用 HTTP':
      'The API URL must use HTTPS. Local emulator addresses may use HTTP.',
  '不支持的协议': 'Unsupported protocol',
  '二维码中没有有效的 API Key': 'The QR code has no valid API key',
  '二维码缺少 API Key': 'The QR code is missing an API key',
  '二维码配置字段格式不正确': 'Invalid configuration fields in the QR code',
  '请扫描仅包含 API Key 字符串的二维码': 'Scan a QR code containing only an API key',
  '请输入有效的 API 根地址': 'Enter a valid API base URL',
  '配置必须是 JSON 对象': 'The configuration must be a JSON object',
  'HTTPS 证书验证失败': 'HTTPS certificate verification failed',
  '服务未返回文本，请检查模型和接口协议':
      'The service returned no text. Check the model and protocol.',
  '服务返回的数据格式不正确，请检查接口协议':
      'The service returned invalid data. Check the protocol.',
  '模型列表格式不正确，请手动输入模型 ID': 'Invalid model list. Enter the model ID manually.',
  '此服务未提供兼容的模型列表': 'This service does not provide a compatible model list',
  '获取模型超时': 'Fetching models timed out',
  '请求超时，请检查网络和 API 地址': 'Request timed out. Check the network and API URL.',
  '连接中断，请检查 API 地址或稍后重试':
      'Connection interrupted. Check the API URL or try again later.',
  '导入失败，请重试': 'Import failed. Try again.',
  '请在系统设置中允许相机权限后返回重试':
      'Allow camera access in system settings, then try again.',
  '相机暂不可用，请检查设备相机后重试':
      'The camera is unavailable. Check the device camera and try again.',
  '扫码后请检查密钥并保存服务。密钥保存在设备安全存储中；选作 Wear OS 服务时会加密同步到手表。Apple Watch 首版不接收密钥。': 'Check the scanned key before saving. It is stored securely on the device and syncs encrypted to Wear OS if selected there. The first Apple Watch version receives no key.',
  '二维码需包含 name、protocol、baseUrl、model、apiKey。\n密钥保存在设备安全存储中；选作 Wear OS 服务时会加密同步到手表，Apple Watch 首版不接收。': 'The QR code must contain name, protocol, baseUrl, model, and apiKey.\nThe key stays in secure device storage; selected Wear OS services sync it encrypted to the watch, while the first Apple Watch version receives no key.',
};
