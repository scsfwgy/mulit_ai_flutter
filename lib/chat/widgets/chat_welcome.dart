import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// 空会话欢迎页：品牌图标、标语与主操作按钮。
class ChatWelcome extends StatelessWidget {
  const ChatWelcome({
    super.key,
    required this.hasProviders,
    required this.onPrimary,
  });

  /// 是否已接入模型服务；决定按钮文案与动作。
  final bool hasProviders;

  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) => Center(
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
              label: hasProviders ? tr('开始新对话') : tr('接入模型服务'),
              onPressed: onPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}
