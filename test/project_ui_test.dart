import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';
import 'package:mulit_ai_flutter/chat/project_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_more_menu.dart';
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
  testWidgets(
    'controlled project filter survives drawer disposal and new chat uses that project',
    (tester) async {
      const channel = MethodChannel('com.tekartik.sqflite');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getDatabasesPath') return '/project-ui-test';
        if (call.method == 'openDatabase') return 1;
        final sql = (call.arguments as Map)['sql'] as String;
        if (call.method != 'query') return null;
        if (sql.contains('user_version')) {
          return [
            {'user_version': 7},
          ];
        }
        if (sql.contains('FROM projects')) {
          return [
            for (var id = 1; id <= 2; id++)
              {
                'id': id,
                'name': 'Project $id',
                'instructions': '',
                'memory': '',
              },
          ];
        }
        if (sql.contains('FROM topics')) {
          return [
            for (var id = 1; id <= 3; id++)
              {
                'id': id,
                'title': 'Chat $id',
                'model': 'qa',
                'updated_at': id,
                'project_id': id == 3 ? null : id,
              },
          ];
        }
        return <Map<String, Object?>>[];
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      int? newProject;
      Future<void> show(ProjectSelection selection) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TopicScreen(
                selection: selection,
                onClose: () {},
                onNew: () {},
                onSettings: () {},
                onChanged: () {},
                onSelect: (_) {},
                onNewInProject: (id) => newProject = id,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(const ProjectSelection(1));
      expect(find.text('Chat 1'), findsOneWidget);
      expect(find.text('Chat 2'), findsNothing);
      await show(const ProjectSelection(2));
      expect(find.text('Chat 1'), findsNothing);
      expect(find.text('Chat 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await show(const ProjectSelection(2));
      expect(find.text('Chat 2'), findsOneWidget);
      expect(find.text('Chat 3'), findsNothing);
      await tester.tap(find.byIcon(CupertinoIcons.square_pencil));
      expect(newProject, 2);
      await show(const ProjectSelection(null, ungrouped: true));
      expect(find.text('Chat 3'), findsOneWidget);
      expect(find.text('Chat 2'), findsNothing);
    },
  );

  testWidgets('More assigns drafts and moves existing project chats', (
    tester,
  ) async {
    var calls = 0;
    for (final assigned in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMoreButton(
              onNewTopic: () {},
              onModel: () {},
              onSettings: () {},
              onMessageSettings: () {},
              onProject: () => calls++,
              projectAssigned: assigned,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(T(assigned ? 'i18n.move_to_project' : 'i18n.add_to_project')),
      );
      await tester.pumpAndSettle();
    }
    expect(calls, 2);
  });
}
