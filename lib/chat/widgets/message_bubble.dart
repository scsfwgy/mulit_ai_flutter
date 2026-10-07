import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectableText;

import 'package:mulit_ai_flutter/chat/assistant_markdown.dart';
import 'package:mulit_ai_flutter/chat/chat_loading_status.dart';
import 'package:mulit_ai_flutter/chat/chat_message_meta.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/search/search_sources.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

/// 单条聊天消息气泡：正文、搜索来源与气泡下方的统计信息。
///
/// 语音播放相关的 [speechState]、[speechEnabled] 与 [onSpeak] 由调用方
/// 依据当前播放状态预先解析后传入，本组件不持有播放状态。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.role,
    required this.content,
    required this.replyElapsedMs,
    required this.searching,
    required this.contextTrimmed,
    required this.speechState,
    required this.speechEnabled,
    required this.onCopy,
    required this.onOpenLink,
    this.loading = false,
    this.messageId,
    this.providerName,
    this.providerPresetId,
    this.modelId,
    this.firstTokenMs,
    this.totalMs,
    this.inputTokens,
    this.outputTokens,
    this.searchSources = const [],
    this.onSpeak,
  });

  final String role;
  final String content;
  final bool loading;
  final int? messageId;
  final String? providerName;
  final String? providerPresetId;
  final String? modelId;
  final int? firstTokenMs;
  final int? totalMs;
  final int? inputTokens;
  final int? outputTokens;
  final List<SearchSource> searchSources;

  /// 生成中气泡的首段可见文字耗时；生成过程中持续更新。
  final ValueListenable<int> replyElapsedMs;

  /// 是否正在联网搜索；影响加载文案。
  final bool searching;

  /// 本次请求是否已按上下文预算裁剪历史。
  final bool contextTrimmed;

  final SpeechPlaybackState speechState;
  final bool speechEnabled;
  final VoidCallback onCopy;
  final ValueChanged<String?> onOpenLink;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
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
                            onTapLink: onOpenLink,
                          ),
                        if (loading)
                          Padding(
                            padding: EdgeInsets.only(
                              top: content.isEmpty ? 2 : 8,
                              bottom: content.isEmpty ? 2 : 0,
                            ),
                            child: ChatLoadingStatus(
                              elapsedMilliseconds: replyElapsedMs,
                              label: searching ? '正在搜索网页…' : '加载中',
                            ),
                          ),
                        if (loading && contextTrimmed)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              tr('已按预算省略较早消息，本机历史保留。'),
                              style: TextStyle(
                                color: IosColors.secondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!user && searchSources.isNotEmpty)
                    SearchSources(
                      key: ValueKey('sources_${messageId ?? 'live'}'),
                      sources: searchSources,
                      onOpen: onOpenLink,
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
                      inputTokens: inputTokens,
                      outputTokens: outputTokens,
                      onCopy: onCopy,
                      speechState: speechState,
                      speechEnabled: speechEnabled,
                      onSpeak: onSpeak,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
