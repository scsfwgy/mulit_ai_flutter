import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/assistant_markdown.dart';
import 'package:mulit_ai_flutter/chat_streaming_reply.dart';

class _BuildCounter extends StatelessWidget {
  const _BuildCounter(this.onBuild);
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const AssistantMarkdown(data: '**Historical reply**');
  }
}

void main() {
  testWidgets(
    'streamed text rebuilds the live bubble without rebuilding history',
    (tester) async {
      final reply = ValueNotifier<String>('');
      addTearDown(reply.dispose);
      var historyBuilds = 0;
      var liveBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                _BuildCounter(() => historyBuilds++),
                ChatStreamingReply(
                  reply: reply,
                  builder: (context, text) {
                    liveBuilds++;
                    return AssistantMarkdown(data: text);
                  },
                ),
              ],
            ),
          ),
        ),
      );
      final initialHistoryBuilds = historyBuilds;
      final initialLiveBuilds = liveBuilds;
      for (var i = 1; i <= 20; i++) {
        reply.value = 'Stream $i';
        await tester.pump();
      }
      expect(historyBuilds, initialHistoryBuilds);
      expect(liveBuilds, initialLiveBuilds + 20);
      expect(
        find.textContaining('Stream 20', findRichText: true),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
