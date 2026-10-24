import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/provider/api_key_help.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/settings/purchase_screen.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/settings/privacy_screen.dart';
import 'package:mulit_ai_flutter/settings/resource_library_screen.dart';
import 'package:mulit_ai_flutter/settings/prompt_screen.dart';
import 'package:mulit_ai_flutter/settings/memory_settings_screen.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/voice/voice_settings_screen.dart';
import 'package:mulit_ai_flutter/search/search_settings_screen.dart';
import 'package:mulit_ai_flutter/watch/watch_settings_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.canClearData});

  final bool Function()? canClearData;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _preferences = AppPreferences.instance;

  Future<void> _openLibrary() async {
    final file = await Navigator.push<StoredChatFile>(
      context,
      appPageRoute(builder: (_) => const ResourceLibraryScreen()),
    );
    if (file != null && mounted) Navigator.pop(context, file);
  }

  Future<void> _chooseLanguage() async {
    final choice = await showAppModalPopup<AppLanguage>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(T('i18n.language')),
        actions: [
          for (final language in AppLanguage.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, language),
              child: Text(_languageName(language)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(T('i18n.cancel')),
        ),
      ),
    );
    if (choice == null) return;
    await _preferences.setLanguage(choice);
    if (mounted) setState(() {});
  }

  String _languageName(AppLanguage language) =>
      languageSelfName(language) ?? T('i18n.follow_system');

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
              T(label),
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
        IosSection(
          children: [
            IosRow(
              title: T('i18n.resource_library'),
              leading: Icon(CupertinoIcons.folder, color: IosColors.blue),
              onTap: _openLibrary,
            ),
          ],
        ),
        IosSection(
          children: [
            IosRow(
              title: T('i18n.context_settings'),
              leading: Icon(
                CupertinoIcons.text_alignleft,
                color: IosColors.blue,
              ),
              onTap: () => Navigator.push<void>(
                context,
                appPageRoute(builder: (_) => const ChatContextScreen()),
              ),
            ),
          ],
        ),
        row(
          'i18n.language',
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
          'i18n.mode',
          CupertinoSlidingSegmentedControl<AppAppearance>(
            groupValue: _preferences.appearance,
            children: {
              for (final mode in AppAppearance.values)
                mode: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    T(switch (mode) {
                      AppAppearance.system => 'i18n.follow_system',
                      AppAppearance.light => 'i18n.light',
                      AppAppearance.dark => 'i18n.dark',
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
          'i18n.accent_color',
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
                          T(skin.label),
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
      title: T('i18n.settings'),
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
                              title: T('i18n.trial_permanent_unlock'),
                              leading: Icon(
                                CupertinoIcons.sparkles,
                                color: IosColors.blue,
                              ),
                              subtitle: T(
                                ApplePurchases.instance.permanent
                                    ? 'i18n.permanently_unlocked'
                                    : 'i18n.7_day_trial_one_time',
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
                      title: T('i18n.resource_library'),
                      leading: Icon(
                        CupertinoIcons.folder,
                        color: IosColors.blue,
                      ),
                      onTap: _openLibrary,
                    ),
                  ],
                ),
                IosSection(
                  children: [
                    IosRow(
                      title: T('i18n.model_settings'),
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
                      title: T('i18n.voice_services'),
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
                      title: T('i18n.web_search'),
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
                        title: T('i18n.watch'),
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
                      title: T('i18n.message_settings'),
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
                      title: T('i18n.language'),
                      subtitle: _languageName(_preferences.language),
                      leading: Icon(
                        CupertinoIcons.globe,
                        color: IosColors.blue,
                      ),
                      onTap: _chooseLanguage,
                    ),
                    IosRow(
                      title: T('i18n.appearance_skin'),
                      subtitle: T(switch (_preferences.appearance) {
                        AppAppearance.system => 'i18n.follow_system',
                        AppAppearance.light => 'i18n.light',
                        AppAppearance.dark => 'i18n.dark',
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
                      title: T('i18n.about'),
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
        (await store.searchApiKey(provider))?.trim().isNotEmpty == true;
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
            content: Text(T('i18n.could_not_save_search_settings')),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(T('i18n.ok')),
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
        title: T('i18n.message_settings'),
        leading: IosNavButton(
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            IosSection(
              footer: T('i18n.your_messages_show_the_model'),
              children: [
                IosRow(
                  title: T('i18n.simple_mode'),
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: AppPreferences.instance.simpleMessageInfo,
                    activeTrackColor: IosColors.blue,
                    onChanged: AppPreferences.instance.setSimpleMessageInfo,
                  ),
                ),
                IosRow(
                  title: T('i18n.web_search'),
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
                  title: T('i18n.read_replies_aloud_automatically'),
                  chevron: false,
                  trailing: CupertinoSwitch(
                    value: AppPreferences.instance.autoReadReplies,
                    activeTrackColor: IosColors.blue,
                    onChanged: AppPreferences.instance.setAutoReadReplies,
                  ),
                ),
                for (final field in ChatInfoField.values)
                  IosRow(
                    title: T(field.label),
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
      title: T('i18n.model_settings'),
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
                title: T('i18n.memory'),
                subtitle: T('i18n.memory_settings_summary'),
                leading: Icon(
                  CupertinoIcons.person_crop_circle,
                  color: IosColors.blue,
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(builder: (_) => const MemorySettingsScreen()),
                ),
              ),
            ],
          ),
          IosSection(
            footer: T('i18n.after_the_first_reply'),
            children: [
              IosRow(
                title: T('i18n.model_services'),
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
                title: T('i18n.prompts'),
                subtitle: T('i18n.global_and_model_prompts'),
                leading: Icon(CupertinoIcons.text_quote, color: IosColors.blue),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(builder: (_) => const PromptSettingsScreen()),
                ),
              ),
              IosRow(
                title: T('i18n.context_settings'),
                leading: Icon(
                  CupertinoIcons.text_alignleft,
                  color: IosColors.blue,
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  appPageRoute(builder: (_) => const ChatContextScreen()),
                ),
              ),
              IosRow(
                title: T('i18n.data_privacy'),
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
        title: Text(T('i18n.mode')),
        actions: [
          for (final mode in AppAppearance.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, mode),
              child: Text(
                T(switch (mode) {
                  AppAppearance.system => 'i18n.follow_system',
                  AppAppearance.light => 'i18n.light',
                  AppAppearance.dark => 'i18n.dark',
                }),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(T('i18n.cancel')),
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
        title: Text(T('i18n.accent_color')),
        actions: [
          for (final skin in AppSkin.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, skin),
              child: Text(T(skin.label)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(T('i18n.cancel')),
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
      title: T('i18n.appearance_skin'),
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
                title: T('i18n.mode'),
                subtitle: switch (_preferences.appearance) {
                  AppAppearance.system => T('i18n.follow_system'),
                  AppAppearance.light => T('i18n.light'),
                  AppAppearance.dark => T('i18n.dark'),
                },
                leading: Icon(CupertinoIcons.moon_stars, color: IosColors.blue),
                onTap: _chooseMode,
              ),
              IosRow(
                title: T('i18n.accent_color'),
                subtitle: T(_preferences.skin.label),
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

  Future<void> _openUrl(String url) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Keep unavailable browsers from surfacing as unhandled platform errors.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(T('i18n.could_not_open_a_browser'))),
      );
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(T('i18n.email_address_copied'))));
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
      title: T('i18n.about'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: T('i18n.app_information'),
            children: [
              IosRow(title: T('AI Link'), chevron: false),
              IosRow(
                title: T('i18n.version'),
                subtitle: _version ?? '…',
                chevron: false,
              ),
              IosRow(
                title: T('i18n.version_code'),
                subtitle: _versionCode ?? '…',
                chevron: false,
              ),
            ],
          ),
          IosSection(
            title: T('i18n.data_privacy'),
            children: [
              _AboutNote(
                title: T('i18n.stored_locally'),
                detail: T('i18n.chats_and_messages_are_stored'),
              ),
              _AboutNote(
                title: T('i18n.direct_requests'),
                detail: T('i18n.requests_go_directly'),
              ),
              IosRow(
                title: T('i18n.privacy_policy'),
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
                title: T('i18n.official_website'),
                subtitle: 'tools24.uk/app/ai-link',
                leading: Icon(CupertinoIcons.globe, color: IosColors.blue),
                onTap: () => _openUrl('https://www.tools24.uk/app/ai-link'),
              ),
              IosRow(
                title: T('i18n.wish_wall'),
                leading: Icon(
                  CupertinoIcons.text_bubble,
                  color: IosColors.blue,
                ),
                onTap: () =>
                    _openUrl('https://www.tools24.uk/app/ai-link/wishes'),
              ),
              const ApiKeyHelpRow(url: apiKeyTutorialUrl),
              IosRow(
                title: T('i18n.contact_and_feedback'),
                subtitle: 'mateolim93@gmail.com',
                leading: Icon(CupertinoIcons.mail, color: IosColors.blue),
                onTap: _contact,
              ),
              IosRow(
                title: T('i18n.open_source_licenses'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: T('AI Link'),
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
