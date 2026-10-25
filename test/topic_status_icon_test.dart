import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

import 'sqflite_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useSqflitePluginFactory();

  testWidgets('topic icons combine persisted watch and search history', (
    tester,
  ) async {
    const channel = MethodChannel('com.tekartik.sqflite');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDatabasesPath') return '/test-topic-icons';
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
            for (var id = 1; id <= 4; id++)
              {
                'id': id,
                'title': 'Topic $id',
                'provider_id': 1,
                'model': 'test-model',
                'updated_at': id,
              },
          ];
        }
        if (sql.contains('FROM messages')) {
          return [
            {'topic_id': 3},
          ];
        }
        if (sql.contains('watch_search_topic_')) {
          return [
            {'value': '4'},
          ];
        }
        if (sql.contains('watch_conversation_')) {
          return [
            {'value': '2'},
            {'value': '4'},
          ];
        }
        return <Map<String, Object?>>[];
      }
      if (call.method == 'execute') return null;
      throw StateError('Unexpected operation: ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopicScreen(
            selectedId: 4,
            onClose: () {},
            onSelect: (_) {},
            onNew: () {},
            onSettings: () {},
            onChanged: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var id = 1; id <= 4; id++) {
      final row = find.ancestor(
        of: find.text('Topic $id'),
        matching: find.byType(IosRow),
      );
      final watch = id == 2 || id == 4;
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(
            watch ? Icons.watch_outlined : CupertinoIcons.chat_bubble_text,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(CupertinoIcons.globe)),
        id >= 3 ? findsOneWidget : findsNothing,
      );
    }
    expect(await ChatStore.instance.searchedTopicIds(), {3, 4});
    expect(tester.takeException(), isNull);
  });
}
