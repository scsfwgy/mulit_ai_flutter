import 'package:flutter/widgets.dart';

/// Only the live bubble subscribes to incoming text; the history and composer
/// keep their existing widgets until request state or another UI state changes.
class ChatStreamingReply extends StatelessWidget {
  const ChatStreamingReply({
    super.key,
    required this.reply,
    required this.builder,
  });

  final ValueNotifier<String> reply;
  final Widget Function(BuildContext context, String text) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: reply,
    builder: (context, text, _) => builder(context, text),
  );
}
