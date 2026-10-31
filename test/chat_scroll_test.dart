import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_scroll.dart';

void main() {
  testWidgets(
    'returning to latest reaches the end of an unbuilt tall reply in one action',
    (tester) async {
      final scroll = ChatScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: scroll.controller,
              itemCount: 40,
              itemBuilder: (_, i) => SizedBox(
                height: i == 39 ? 6000 : 60,
                child: Text('message $i'),
              ),
            ),
          ),
        ),
      );
      scroll.scrollToLatest(force: true);
      await tester.pumpAndSettle();
      expect(scroll.controller.position.extentAfter, lessThanOrEqualTo(1));
      expect(scroll.showLatest.value, false);
    },
  );

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
    expect(chatScroll.showLatest.value, true);
    expect(
      readingOffset,
      lessThan(chatScroll.controller.position.maxScrollExtent),
    );

    rebuild(() => replyHeight += 300);
    chatScroll.scrollToLatest();
    await tester.pump();
    expect(chatScroll.controller.offset, readingOffset);

    chatScroll.scrollToLatest(force: true);
    await tester.pump();
    expect(chatScroll.showLatest.value, false);
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
