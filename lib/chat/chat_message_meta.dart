import 'package:flutter/cupertino.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/chat/message_copy.dart';
import 'package:mulit_ai_flutter/provider/provider_badge.dart';

enum SpeechPlaybackState { idle, loading, playing }

class ChatMessageMeta extends StatelessWidget {
  const ChatMessageMeta({
    super.key,
    required this.assistant,
    required this.content,
    this.modelId,
    this.providerName,
    this.providerPresetId,
    this.firstTokenMs,
    this.totalMs,
    this.inputTokens,
    this.outputTokens,
    this.onCopy,
    this.onSpeak,
    this.speechState = SpeechPlaybackState.idle,
    this.speechEnabled = true,
  });

  final bool assistant;
  final String content;
  final String? modelId;
  final String? providerName;
  final String? providerPresetId;
  final int? firstTokenMs;
  final int? totalMs;
  final int? inputTokens;
  final int? outputTokens;
  final VoidCallback? onCopy;
  final VoidCallback? onSpeak;
  final SpeechPlaybackState speechState;
  final bool speechEnabled;

  String _time(int? milliseconds) {
    if (milliseconds == null) return '—';
    if (milliseconds < 1000) return '${milliseconds}ms';
    return '${(milliseconds / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    final parts = <String>[
      if (assistant &&
          firstTokenMs != null &&
          preferences.showChatInfo(ChatInfoField.firstFrame))
        '${T('i18n.first_text')} ${_time(firstTokenMs)}',
      if (assistant &&
          totalMs != null &&
          preferences.showChatInfo(ChatInfoField.totalTime))
        '${T('i18n.time')} ${_time(totalMs)}',
      if (assistant && preferences.showChatInfo(ChatInfoField.tokens)) ...[
        if (inputTokens != null || outputTokens != null) ...[
          '${T('i18n.input')} ${inputTokens ?? '—'}',
          '${T('i18n.output')} ${outputTokens ?? '—'}',
        ] else if (modelId != null)
          'Token —',
      ],
      if (preferences.showChatInfo(ChatInfoField.characters))
        '${visibleCharacterCount(assistant ? readableMarkdown(content) : content)} ${T('i18n.chars')}',
    ];
    final showIdentity = preferences.showChatInfo(ChatInfoField.modelId);
    final showModel = modelId != null && showIdentity;
    final showProvider = providerName != null && showIdentity;
    final showCopy =
        onCopy != null && preferences.showChatInfo(ChatInfoField.copy);
    final showSpeech =
        assistant &&
        onSpeak != null &&
        preferences.showChatInfo(ChatInfoField.speech);
    if (!showProvider &&
        !showModel &&
        parts.isEmpty &&
        !showCopy &&
        !showSpeech) {
      return const SizedBox.shrink();
    }
    final style = TextStyle(
      color: IosColors.secondary,
      fontSize: 11,
      height: 1.2,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: assistant ? WrapAlignment.start : WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 9,
        runSpacing: 0,
        children: [
          if (showProvider)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .62,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProviderBadge(
                    name: providerName!,
                    presetId: providerPresetId,
                    size: 17,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      providerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        color: IosColors.label.withValues(alpha: .75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showModel)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .7,
              ),
              child: Text(
                modelId!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(
                  color: IosColors.label.withValues(alpha: .75),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          for (final part in parts) Text(part, style: style),
          if (showCopy)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 32),
              onPressed: onCopy,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: IosColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: IosColors.separator, width: .5),
                ),
                child: SizedBox(
                  width: 27,
                  height: 25,
                  child: Center(
                    child: Icon(
                      CupertinoIcons.doc_on_doc,
                      size: 14,
                      color: IosColors.secondary,
                      semanticLabel: T('i18n.copy_message'),
                    ),
                  ),
                ),
              ),
            ),
          if (showSpeech)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 32),
              onPressed:
                  speechEnabled && speechState != SpeechPlaybackState.loading
                  ? onSpeak
                  : null,
              child: SpeechPlaybackIndicator(state: speechState),
            ),
        ],
      ),
    );
  }
}

class SpeechPlaybackIndicator extends StatefulWidget {
  const SpeechPlaybackIndicator({super.key, required this.state});
  final SpeechPlaybackState state;

  @override
  State<SpeechPlaybackIndicator> createState() =>
      _SpeechPlaybackIndicatorState();
}

class _SpeechPlaybackIndicatorState extends State<SpeechPlaybackIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    lowerBound: .55,
    upperBound: 1,
  );

  @override
  void initState() {
    super.initState();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(SpeechPlaybackIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.state == SpeechPlaybackState.playing &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
      _animation.repeat(reverse: true);
    } else {
      _animation.stop();
      _animation.value = 1;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: T(switch (widget.state) {
      SpeechPlaybackState.idle => 'i18n.read_reply_aloud',
      SpeechPlaybackState.loading => 'i18n.generating_speech',
      SpeechPlaybackState.playing => 'i18n.stop_reading_aloud',
    }),
    child: SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: widget.state == SpeechPlaybackState.loading
            ? const CupertinoActivityIndicator(radius: 7)
            : FadeTransition(
                opacity: _animation,
                child: Icon(
                  CupertinoIcons.speaker_2,
                  size: 17,
                  color: widget.state == SpeechPlaybackState.playing
                      ? IosColors.blue
                      : IosColors.secondary,
                ),
              ),
      ),
    ),
  );
}
