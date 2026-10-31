import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/assistant_markdown.dart';
import 'package:mulit_ai_flutter/chat/project_screen.dart';
import 'package:mulit_ai_flutter/core/project.dart';

import 'sqflite_stub.dart';

void main() {
  setUpAll(useSqflitePluginFactory);
  testWidgets(
    'Markdown knowledge renders headings and tables and copies original text without loading images',
    (tester) async {
      const content =
          '# Heading\n\n**Emphasis**\n\n| Item | Value |\n|---|---|\n| A | 2 |\n\n![Local preview](https://example.com/tracking.png)';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.tekartik.sqflite');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getDatabasesPath') return '/knowledge-preview';
        if (call.method == 'openDatabase') return 1;
        final args = call.arguments as Map;
        final sql = args['sql'] as String? ?? '';
        if (call.method == 'query') {
          if (sql.contains('user_version')) {
            return [
              {'user_version': 7},
            ];
          }
          if (sql.contains('FROM knowledge_documents')) {
            if (sql.startsWith('SELECT content')) {
              return [
                {'content': content},
              ];
            }
            return [
              {'id': 1, 'name': 'Report.md', 'characters': content.length},
            ];
          }
          return <Map<String, Object?>>[];
        }
        return null;
      });
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: ProjectScreen(project: ChatProject(id: 1, name: 'Project')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report.md'));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantMarkdown), findsOneWidget);
      expect(find.text('Heading', findRichText: true), findsOneWidget);
      expect(find.text('A', findRichText: true), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byIcon(CupertinoIcons.doc_on_doc));
      await tester.pump();
      expect(copied, content);
      expect(tester.takeException(), isNull);
    },
  );
}
