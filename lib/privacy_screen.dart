import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'app_preferences.dart';
import 'ios_style.dart';

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
      setState(() => _error = tr('请先停止回复或等待标题生成完成，再清空数据。'));
      return;
    }
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(tr('清空本地数据？')),
        content: Text(
          tr(
            '手机上的话题、聊天记录、服务配置、API Key 和提示词会被删除。已同步到手表的配置与离线记录需在手表上卸载应用才能清除。此操作无法撤销。',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('取消')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('清空')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.canClearData?.call() == false) {
      setState(() => _error = tr('请先停止回复或等待标题生成完成，再清空数据。'));
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
        setState(() => _error = '清理未完成，请重试。');
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: '数据与隐私',
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: ListView(
        children: [
          IosSection(
            title: '数据存放',
            children: [
              _PrivacyRow(
                title: 'API Key',
                detail: tr('保存在设备的安全存储中，不写入聊天数据库。'),
              ),
              _PrivacyRow(
                title: '聊天与配置',
                detail: tr('话题、消息、提示词和非密钥配置保存在本机数据库中，数据库内容未加密。'),
              ),
              _PrivacyRow(
                title: '模型请求',
                detail: tr('对话内容、提示词和 API Key 从设备直接发送到你选择的服务地址，由该服务处理。'),
              ),
              _PrivacyRow(
                title: '手表数据',
                detail: tr(
                  '手表会加密保存所选服务的密钥，并在应用私有存储中保存离线问答；重连后将问答同步到手机。清空手机数据不会清除离线手表数据。',
                ),
              ),
            ],
          ),
          IosSection(
            title: '本地数据管理',
            footer: '清空后无法在应用内恢复聊天记录。已经发送给第三方模型服务的内容不受此操作影响。',
            children: [
              _PrivacyRow(
                title: '单独删除',
                detail: tr('可在话题列表删除某个话题，在模型服务页删除某项服务及其密钥。'),
              ),
            ],
          ),
          IosSection(
            children: [
              IosRow(
                title: tr('完整隐私政策'),
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
                title: _clearing ? '正在清空…' : '清空所有本地数据',
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
                tr(_error!),
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
            tr(title),
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
