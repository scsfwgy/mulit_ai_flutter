import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, this.clearData, this.canClearData});

  final Future<void> Function()? clearData;
  final bool Function()? canClearData;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _clearing = false;
  String? _error;

  Future<void> _clear() async {
    if (_clearing) return;
    if (widget.canClearData?.call() == false) {
      setState(() => _error = T('i18n.stop_the_reply_or_wait'));
      return;
    }
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(T('i18n.clear_local_data')),
        content: Text(
          T(
            isDesktopApp
                ? 'i18n.topics_messages_service_settings_api'
                : 'i18n.chats_service_settings_api_keys',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(T('i18n.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(T('i18n.clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.canClearData?.call() == false) {
      setState(() => _error = T('i18n.stop_the_reply_or_wait'));
      return;
    }
    setState(() {
      _clearing = true;
      _error = null;
    });
    try {
      await (widget.clearData ?? ChatStore.instance.clearAllData)();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = T('i18n.could_not_finish_clearing_data'));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: T('i18n.data_privacy'),
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: T('i18n.storage'),
            children: [
              _PrivacyRow(
                title: 'API Key',
                detail: T('i18n.stored_in_the_device_secure'),
              ),
              _PrivacyRow(
                title: T('i18n.chats_settings'),
                detail: T('i18n.chats_messages_prompts_and_settings'),
              ),
              _PrivacyRow(
                title: T('i18n.model_requests'),
                detail: T('i18n.chats_prompts_and_api_keys'),
              ),
              _PrivacyRow(
                title: T('i18n.web_search'),
                detail: T(
                  isDesktopApp
                      ? 'i18n.when_web_search_is_enabled'
                      : 'i18n.web_search_privacy_watch',
                ),
              ),
              if (supportsWatchCompanion)
                _PrivacyRow(
                  title: T('i18n.watch_data'),
                  detail: T(
                    'i18n.watches_securely_store_selected_service',
                  ),
                ),
              if (ApplePurchases.instance.enabled)
                _PrivacyRow(
                  title: T('i18n.purchases_and_trial'),
                  detail: T(
                    'i18n.app_store_handles_apple_purchases',
                  ),
                ),
              _PrivacyRow(
                title: T('i18n.usage_analytics'),
                detail: T(
                  isDesktopApp ? 'i18n.the_macos_app_does' : 'i18n.android_and_ios_production_builds',
                ),
              ),
            ],
          ),
          IosSection(
            title: T('i18n.local_data'),
            footer: T('i18n.cleared_chats_cannot_be_recovered'),
            children: [
              _PrivacyRow(
                title: T('i18n.delete_individually'),
                detail: T('i18n.delete_individual_chats_in_chats'),
              ),
            ],
          ),
          IosSection(
            children: [
              IosRow(
                title: T('i18n.full_privacy_policy'),
                subtitle: 'tools24.uk/app/ai-link/privacy',
                leading: Icon(
                  CupertinoIcons.doc_text,
                  color: IosColors.blue,
                  size: 22,
                ),
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
                title: _clearing ? T('i18n.clearing') : T('i18n.clear_all_local_data'),
                leading: Icon(
                  CupertinoIcons.delete,
                  color: IosColors.destructive,
                  size: 22,
                ),
                chevron: false,
                onTap: _clearing ? null : _clear,
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 12, 30, 0),
              child: Text(
                T(_error!),
                style: TextStyle(color: IosColors.destructive),
              ),
            ),
          const SizedBox(height: 30),
        ],
      ),
    ),
  );
}

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            T(title),
            style: TextStyle(color: IosColors.label, fontSize: 16),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: TextStyle(
              color: IosColors.secondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    ),
  );
}
