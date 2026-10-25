import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

import 'sqflite_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useSqflitePluginFactory();
  testWidgets('search clears back to normal topic actions and pin persists', (
    tester,
  ) async {
    var pinned = false;
    const channel = MethodChannel('com.tekartik.sqflite');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDatabasesPath') return '/project-ui-test';
      if (call.method == 'openDatabase') return 1;
      final args = call.arguments as Map;
      final sql = args['sql'] as String;
      if (call.method == 'query') {
        if (sql.contains('user_version')) {
          return [
            {'user_version': 7},
          ];
        }
        if (sql.contains('FROM topics')) {
          return [
            {
              'id': 1,
              'title': 'Cache discussion',
              'model': 'qa',
              'updated_at': 1,
              'pinned_at': pinned ? 100 : 0,
              if (sql.contains('LEFT JOIN')) ...{
                'match_id': 2,
                'match_content': 'cache expires after 30 minutes',
              },
            },
          ];
        }
        return <Map<String, Object?>>[];
      }
      if (call.method == 'update') {
        pinned = true;
        return 1;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    int? located;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopicScreen(
            persistent: true,
            onClose: () {},
            onNew: () {},
            onSettings: () {},
            onChanged: () {},
            onSelect: (_) {},
            onSearchSelect: (_, message) => located = message,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoSearchTextField), '30 minutes');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('cache expires after 30 minutes'), findsOneWidget);
    await tester.tap(find.text('Cache discussion'));
    expect(located, 2);
    await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<CupertinoSearchTextField>(
            find.byType(CupertinoSearchTextField),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text(T('i18n.history_matches')), findsNothing);
    final row = find.ancestor(
      of: find.text('Cache discussion'),
      matching: find.byType(IosRow),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(CupertinoIcons.ellipsis)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(T('i18n.pin_chat')));
    await tester.pumpAndSettle();
    expect(pinned, isTrue);
    expect(find.textContaining(T('i18n.pinned_chat')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
