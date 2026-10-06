import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_key_help.dart';
import 'apple_purchases.dart';
import 'purchase_screen.dart';
import 'app_platform.dart';

import 'app_preferences.dart';
import 'data.dart';
import 'ios_style.dart';
import 'privacy_screen.dart';
import 'prompt_screen.dart';
import 'provider_screen.dart';
import 'voice_settings_screen.dart';
import 'search_settings_screen.dart';
import 'watch_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.canClearData});

  final bool Function()? canClearData;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _preferences = AppPreferences.instance;

  Future<void> _chooseLanguage() async {
    final choice = await showAppModalPopup<AppLanguage>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('语言')),
        actions: [
          for (final language in AppLanguage.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, language),
              child: Text(_languageName(language)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (choice == null) return;
    await _preferences.setLanguage(choice);
    if (mounted) setState(() {});
  }

  String _languageName(AppLanguage language) => switch (language) {
    AppLanguage.system => tr('跟随系统'),
    AppLanguage.zh => '简体中文',
    AppLanguage.en => 'English',
  };

  Future<void> _openPrivacy() async {
    final cleared = await Navigator.push<bool>(
      context,
      appPageRoute(
        builder: (_) => PrivacyScreen(canClearData: widget.canClearData),
      ),
    );
    if (cleared == true) await _preferences.load();
    if (mounted) setState(() {});
  }

  Widget _desktopPreferences() {
    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              tr(label),
              style: TextStyle(fontSize: 15, color: IosColors.label),
            ),
          ),
          Expanded(child: control),
        ],
      ),
    );
    Future<void> save(Future<void> operation) async {
      await operation;
      if (mounted) setState(() {});
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
      children: [
        row(
          '语言',
          CupertinoSlidingSegmentedControl<AppLanguage>(
            groupValue: _preferences.language,
            children: {
              for (final language in AppLanguage.values)
                language: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_languageName(language)),
                ),
            },
            onValueChanged: (value) {
              if (value != null) save(_preferences.setLanguage(value));
            },
          ),
        ),
        Divider(color: IosColors.separator),
        row(
          '模式',
          CupertinoSlidingSegmentedControl<AppAppearance>(
            groupValue: _preferences.appearance,
            children: {
              for (final mode in AppAppearance.values)
                mode: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    tr(switch (mode) {
                      AppAppearance.system => '跟随系统',
                      AppAppearance.light => '白天',
                      AppAppearance.dark => '黑夜',
                    }),
                  ),
                ),
            },
            onValueChanged: (value) {
              if (value != null) save(_preferences.setAppearance(value));
            },
          ),
        ),
        Divider(color: IosColors.separator),
        row(
          '主题色',
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final skin in AppSkin.values)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: IosColors.surface,
                    border: Border.all(
                      color: _preferences.skin == skin
                          ? IosColors.blue
                          : IosColors.separator,
                      width: _preferences.skin == skin ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    onPressed: () => save(_preferences.setSkin(skin)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.circle_fill,
                          color: skin.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr(skin.label),
                          style: TextStyle(
                            color: IosColors.label,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: tr('设置'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: isDesktopApp
        ? _desktopPreferences()
        : SafeArea(
            child: ListView(
              children: [
                AnimatedBuilder(
                  animation: ApplePurchases.instance,
                  builder: (context, _) => ApplePurchases.instance.enabled
                      ? IosSection(
                          children: [
                            IosRow(
                              title: tr('试用与永久解锁'),
                              leading: Icon(
                                CupertinoIcons.sparkles,
                                color: IosColors.blue,
                              ),
                              subtitle: tr(
                                ApplePurchases.instance.permanent
                                    ? '已永久解锁'
                                    : '7 天试用，一次买断',
                              ),
                              onTap: () => Navigator.push<void>(
                                context,
                                appPageRoute(
                                  builder: (_) => const PurchaseScreen(),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                IosSection(
                  children: [
                    IosRow(
                      title: tr('模型设置'),
                      leading: Icon(
                        CupertinoIcons.square_stack,
                        color: IosColors.blue,
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        appPageRoute(
                          builder: (_) => ModelSettingsScreen(
                            canClearData: widget.canClearData,
                            onPrivacy: _openPrivacy,
                          ),
                        ),
                      ),
                    ),
                    IosRow(
                      title: tr('语音服务'),
                      leading: Icon(
                        CupertinoIcons.waveform,
                        color: IosColors.blue,
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        appPageRoute(
                          builder: (_) => const VoiceSettingsScreen(),
                        ),
                      ),
                    ),
                    IosRow(
                      title: tr('联网搜索'),
                      leading: Icon(
                        CupertinoIcons.search,
                        color: IosColors.blue,
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        appPageRoute(
                          builder: (_) => const SearchSettingsScreen(),
                        ),
                      ),
                    ),
                    if (supportsWatchCompanion)
                      IosRow(
                        title: tr('手表'),
                        leading: Icon(
                          CupertinoIcons.device_phone_portrait,
                          color: IosColors.blue,
                        ),
                        onTap: () => Navigator.push<void>(
                          context,
                          appPageRoute(
                            builder: (_) => const WatchSettingsScreen(),
                          ),
                        ),
                      ),
                    IosRow(
                      title: tr('消息设置'),
                      leading: Icon(CupertinoIcons.info, color: IosColors.blue),
                      onTap: () => Navigator.push<void>(
                        context,
                        appPageRoute(
                          builder: (_) => MessageSettingsScreen(
                            canChangeSearch: widget.canClearData,
                          ),
                        ),
                      ),
                    ),
                    IosRow(
                      title: tr('语言'),
                      subtitle: _languageName(_preferences.language),
                      leading: Icon(
                        CupertinoIcons.globe,
                        color: IosColors.blue,
                      ),
                      onTap: _chooseLanguage,
                    ),
                    IosRow(
                      title: tr('换肤'),
                      subtitle: tr(switch (_preferences.appearance) {
                        AppAppearance.system => '跟随系统',
                        AppAppearance.light => '白天',
                        AppAppearance.dark => '黑夜',
                      }),
                      leading: Icon(
                        CupertinoIcons.paintbrush,
                        color: IosColors.blue,
                      ),
                      onTap: () =>
                          Navigator.push<void>(
                            context,
                            appPageRoute(
                              builder: (_) => const AppearanceScreen(),
                            ),
                          ).then((_) {
                            if (mounted) setState(() {});
                          }),
                    ),
                    IosRow(
                      title: tr('关于'),
                      leading: Icon(
                        CupertinoIcons.info_circle,
                        color: IosColors.blue,
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        appPageRoute(builder: (_) => const AboutScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
  );
}

class MessageSettingsScreen extends StatefulWidget {
  const MessageSettingsScreen({super.key, this.canChangeSearch});

  final bool Function()? canChangeSearch;

  @override
  State<MessageSettingsScreen> createState() => _MessageSettingsScreenState();
}

class _MessageSettingsScreenState extends State<MessageSettingsScreen> {
  bool _searchEnabled = false;
  bool _loadingSearch = true;
  bool _savingSearch = false;

  @override
  void initState() {
    super.initState();
    _loadSearch();
  }

  Future<void> _loadSearch() async {
    try {
      final enabled = await ChatStore.instance.setting('search_enabled') == '1';
      if (mounted) setState(() => _searchEnabled = enabled);
    } catch (_) {
      // Keep settings accessible if local storage is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _loadingSearch = false);
    }
  }

  Future<bool> _searchConfigured() async {
    final store = ChatStore.instance;
    final provider = await store.selectedSearchProvider();
    return provider != null &&
        (await store.searchApiKey(provider.id))?.trim().isNotEmpty == true;
  }

  Future<void> _setSearchEnabled(bool enabled) async {
    if (_loadingSearch ||
        _savingSearch ||
        !(widget.canChangeSearch?.call() ?? true)) {
      return;
    }
    setState(() => _savingSearch = true);
    try {
      if (enabled && !await _searchConfigured()) {
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          appPageRoute(builder: (_) => const SearchSettingsScreen()),
        );
        if (!mounted || !await _searchConfigured()) return;
      }
      if (!(widget.canChangeSearch?.call() ?? true)) return;
      await ChatStore.instance.saveSetting(
        'search_enabled',
        enabled ? '1' : '0',
      );
      if (mounted) setState(() => _searchEnabled = enabled);
    } catch (_) {
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            content: Text(tr('无法保存搜索配置，请重试。')),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('好')),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSearch = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (context, _) => Scaffold(
      backgroundColor: IosColors.background,
      appBar: iosAppBar(
        title: tr('消息设置'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            IosSection(
              footer: tr(
                '用户消息显示模型与字数；耗时和 Token 属于整次回复请求。旧消息缺少的统计不显示；服务未提供用量时显示 Token —。',
              ),
              children: [
                IosRow(
                  title: '简洁模式',
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: AppPreferences.instance.simpleMessageInfo,
                    activeTrackColor: IosColors.blue,
                    onChanged: AppPreferences.instance.setSimpleMessageInfo,
                  ),
                ),
                IosRow(
                  title: '联网搜索',
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: _searchEnabled,
                    activeTrackColor: IosColors.blue,
                    onChanged:
                        _loadingSearch ||
                            _savingSearch ||
                            !(widget.canChangeSearch?.call() ?? true)
                        ? null
                        : _setSearchEnabled,
                  ),
                ),
                IosRow(
                  title: '回复完成后自动朗读',
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: AppPreferences.instance.autoReadReplies,
                    activeTrackColor: IosColors.blue,
                    onChanged: AppPreferences.instance.setAutoReadReplies,
                  ),
                ),
                for (final field in ChatInfoField.values)
                  IosRow(
                    title: tr(field.label),
                    chevron: false,
                    trailing: CupertinoSwitch(
                      value: AppPreferences.instance.showChatInfo(field),
                      activeTrackColor: IosColors.blue,
                      onChanged: AppPreferences.instance.simpleMessageInfo
                          ? null
                          : (value) => AppPreferences.instance
                                .setChatInfoVisible(field, value),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ModelSettingsScreen extends StatelessWidget {
  const ModelSettingsScreen({
    super.key,
    this.canClearData,
    required this.onPrivacy,
  });

  final bool Function()? canClearData;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: '模型设置',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            footer: '首轮回复后，会额外请求当前模型生成会话标题，可能产生少量用量。',
            children: [
              IosRow(
                title: '模型服务',
                leading: Icon(
                  CupertinoIcons.square_stack,
                  color: IosColors.blue,
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(
                    builder: (_) => ProviderScreen(canClearData: canClearData),
                  ),
                ),
              ),
              IosRow(
                title: '提示词',
                subtitle: '全局和单模型提示词',
                leading: Icon(CupertinoIcons.text_quote, color: IosColors.blue),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(builder: (_) => const PromptSettingsScreen()),
                ),
              ),
              IosRow(
                title: '数据与隐私',
                leading: Icon(
                  CupertinoIcons.lock_shield,
                  color: IosColors.blue,
                ),
                onTap: onPrivacy,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final _preferences = AppPreferences.instance;

  Future<void> _chooseMode() async {
    final choice = await showAppModalPopup<AppAppearance>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('模式')),
        actions: [
          for (final mode in AppAppearance.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, mode),
              child: Text(
                tr(switch (mode) {
                  AppAppearance.system => '跟随系统',
                  AppAppearance.light => '白天',
                  AppAppearance.dark => '黑夜',
                }),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (choice == null) return;
    await _preferences.setAppearance(choice);
    if (mounted) setState(() {});
  }

  Future<void> _chooseSkin() async {
    final choice = await showAppModalPopup<AppSkin>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(tr('主题色')),
        actions: [
          for (final skin in AppSkin.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, skin),
              child: Text(tr(skin.label)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(tr('取消')),
        ),
      ),
    );
    if (choice == null) return;
    await _preferences.setSkin(choice);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: '换肤',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            children: [
              IosRow(
                title: '模式',
                subtitle: switch (_preferences.appearance) {
                  AppAppearance.system => '跟随系统',
                  AppAppearance.light => '白天',
                  AppAppearance.dark => '黑夜',
                },
                leading: Icon(CupertinoIcons.moon_stars, color: IosColors.blue),
                onTap: _chooseMode,
              ),
              IosRow(
                title: '主题色',
                subtitle: _preferences.skin.label,
                leading: Icon(CupertinoIcons.paintbrush, color: IosColors.blue),
                onTap: _chooseSkin,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;
  String? _versionCode;

  Future<void> _openWebsite() async {
    await launchUrl(
      Uri.parse('https://www.tools24.uk/app/ai-link'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _contact() async {
    const address = 'mateolim93@gmail.com';
    try {
      if (await launchUrl(Uri(scheme: 'mailto', path: address))) return;
    } catch (_) {
      // A mail client is optional; keep the support address usable.
    }
    await Clipboard.setData(const ClipboardData(text: address));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('邮箱已复制'))));
    }
  }

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((info) {
          if (mounted) {
            const channel = String.fromEnvironment('APP_CHANNEL');
            final suffix = switch (channel) {
              'google_play' => '(gp)',
              'official' => '(site)',
              _ => '',
            };
            setState(() {
              _version = '${info.version}$suffix';
              _versionCode = info.buildNumber;
            });
          }
        })
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: tr('关于'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: tr('应用信息'),
            children: [
              IosRow(title: tr('AI Link'), chevron: false),
              IosRow(
                title: tr('版本'),
                subtitle: _version ?? '…',
                chevron: false,
              ),
              IosRow(
                title: tr('版本 Code'),
                subtitle: _versionCode ?? '…',
                chevron: false,
              ),
            ],
          ),
          IosSection(
            title: tr('数据与隐私'),
            children: [
              _AboutNote(
                title: tr('本地保存'),
                detail: tr('话题和消息保存在设备的 SQLite 数据库中。API Key 保存在系统安全存储中。'),
              ),
              _AboutNote(title: tr('请求直连'), detail: tr('请求从设备直接发送到你配置的模型服务商。')),
              IosRow(
                title: tr('隐私协议'),
                subtitle: 'tools24.uk/app/ai-link/privacy',
                leading: Icon(CupertinoIcons.doc_text, color: IosColors.blue),
                onTap: () => launchUrl(
                  Uri.parse('https://www.tools24.uk/app/ai-link/privacy'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          IosSection(
            children: [
              IosRow(
                title: tr('官方网站'),
                subtitle: 'tools24.uk/app/ai-link',
                leading: Icon(CupertinoIcons.globe, color: IosColors.blue),
                onTap: _openWebsite,
              ),
              const ApiKeyHelpRow(url: apiKeyTutorialUrl),
              IosRow(
                title: tr('联系与反馈'),
                subtitle: 'mateolim93@gmail.com',
                leading: Icon(CupertinoIcons.mail, color: IosColors.blue),
                onTap: _contact,
              ),
              IosRow(
                title: tr('开源许可'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: tr('AI Link'),
                  applicationVersion: _version,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AboutNote extends StatelessWidget {
  const _AboutNote({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: TextStyle(fontSize: 13, color: IosColors.secondary),
          ),
        ],
      ),
    ),
  );
}
