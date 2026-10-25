import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_more_menu.dart';
import 'package:mulit_ai_flutter/chat/desktop_chat.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

import 'sqflite_stub.dart';

void main() {
  setUpAll(useSqflitePluginFactory);
  testWidgets(
    'desktop header lines align and More opens a compact anchored menu',
    (tester) async {
      installEmptyDatabaseStub();
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var projectCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopChatLayout(
            showSidebar: true,
            sidebar: TopicScreen(
              persistent: true,
              onClose: () {},
              onSelect: (_) {},
              onNew: () {},
              onSettings: () {},
              onChanged: () {},
            ),
            chat: Scaffold(
              appBar: iosAppBar(
                title: 'Model',
                actions: [
                  ChatMoreButton(
                    onNewTopic: () {},
                    onModel: () {},
                    onSettings: () {},
                    onMessageSettings: () {},
                    onProject: () => projectCalls++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('AI Link');
      final header = find
          .ancestor(
            of: title,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.height == desktopToolbarHeight,
            ),
          )
          .first;
      expect(
        tester.getBottomLeft(header).dy,
        closeTo(tester.getBottomLeft(find.byType(AppBar)).dy, .5),
      );
      final button = find.byType(ChatMoreButton);
      final buttonRect = tester.getRect(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final popup = find.byKey(const ValueKey('desktop-popup-menu'));
      expect(popup, findsOneWidget);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      final rect = tester.getRect(popup);
      expect(rect.width, lessThanOrEqualTo(224));
      expect(rect.height, lessThanOrEqualTo(210));
      expect(rect.top, greaterThanOrEqualTo(buttonRect.bottom));
      expect((rect.right - buttonRect.right).abs(), lessThanOrEqualTo(8));
      await tester.tap(find.text(T('i18n.add_to_project')));
      await tester.pumpAndSettle();
      expect(projectCalls, 1);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 400));
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(popup, findsNothing);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}
