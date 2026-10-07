import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// 聊天页错误提示可执行的动作类型，决定卡片上出现哪些修复入口。
enum ChatErrorAction { none, configure, model, request, retry, search, context }

/// 聊天页底部错误卡片。
///
/// 只负责展示与回调转发；`messageKey` 为待翻译的文案键，
/// 由本组件在渲染时调用 [tr] 解析。
class ChatErrorCard extends StatelessWidget {
  const ChatErrorCard({
    super.key,
    required this.messageKey,
    required this.action,
    required this.canRetryFromLastUser,
    required this.onCheckProvider,
    required this.onCheckSearch,
    required this.onRetry,
    required this.onAdjustContext,
    required this.onNewTopic,
    required this.onChangeModel,
  });

  final String messageKey;
  final ChatErrorAction action;

  /// 最后一条消息是否为用户消息；决定上下文超限时是否给出「重试回复」。
  final bool canRetryFromLastUser;

  final VoidCallback onCheckProvider;
  final VoidCallback onCheckSearch;
  final VoidCallback onRetry;
  final VoidCallback onAdjustContext;
  final VoidCallback onNewTopic;
  final VoidCallback onChangeModel;

  @override
  Widget build(BuildContext context) => Container(
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
          tr(messageKey),
          style: TextStyle(color: IosColors.destructive, fontSize: 13),
        ),
        if (action != ChatErrorAction.none)
          Wrap(
            spacing: 8,
            children: [
              if (action == ChatErrorAction.configure ||
                  action == ChatErrorAction.request ||
                  action == ChatErrorAction.retry)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: onCheckProvider,
                  child: Text(
                    action == ChatErrorAction.configure
                        ? tr('检查密钥')
                        : tr('检查服务配置'),
                  ),
                ),
              if (action == ChatErrorAction.search)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: onCheckSearch,
                  child: Text(tr('检查搜索配置')),
                ),
              if (action == ChatErrorAction.retry ||
                  action == ChatErrorAction.search ||
                  (action == ChatErrorAction.context && canRetryFromLastUser))
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: onRetry,
                  child: Text(tr('重试回复')),
                ),
              if (action == ChatErrorAction.context) ...[
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: onAdjustContext,
                  child: Text(tr('调整上下文')),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: onNewTopic,
                  child: Text(tr('新对话')),
                ),
              ],
              if (action == ChatErrorAction.model ||
                  action == ChatErrorAction.request)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                  onPressed: onChangeModel,
                  child: Text(tr('切换模型')),
                ),
            ],
          ),
      ],
    ),
  );
}
