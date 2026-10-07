import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_scroll.dart';

void main() {
  testWidgets('streaming follows the bottom until the user scrolls away', (
    tester,
  ) async {
    final chatScroll = ChatScrollController();
    addTearDown(chatScroll.dispose);
    late StateSetter rebuild;
    var replyHeight = 80.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return NotificationListener<ScrollNotification>(
                onNotification: chatScroll.onScrollNotification,
                child: ListView.builder(
                  controller: chatScroll.controller,
                  itemCount: 21,
                  itemBuilder: (context, index) => SizedBox(
                    height: index == 20 ? replyHeight : 60,
                    child: Text('message $index'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    chatScroll.scrollToLatest(force: true);
    await tester.pump();
    expect(
      chatScroll.controller.offset,
      chatScroll.controller.position.maxScrollExtent,
    );

    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    final readingOffset = chatScroll.controller.offset;
    expect(
      readingOffset,
      lessThan(chatScroll.controller.position.maxScrollExtent),
    );

    rebuild(() => replyHeight += 300);
    chatScroll.scrollToLatest();
    await tester.pump();
    expect(chatScroll.controller.offset, readingOffset);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(
      chatScroll.controller.offset,
      chatScroll.controller.position.maxScrollExtent,
    );

    rebuild(() => replyHeight += 300);
    chatScroll.scrollToLatest();
    await tester.pump();
    expect(
      chatScroll.controller.offset,
      chatScroll.controller.position.maxScrollExtent,
    );
  });
}
