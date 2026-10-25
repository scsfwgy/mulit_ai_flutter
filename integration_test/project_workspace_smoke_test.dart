import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mulit_ai_flutter/chat/project_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_home.dart';
import 'package:mulit_ai_flutter/chat/chat_more_menu.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';
import 'package:mulit_ai_flutter/chat/widgets/knowledge_sources.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class _WorkspaceTestBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  void scheduleFrame() {
    if (framesEnabled) {
      super.scheduleFrame();
    } else {
      super.scheduleForcedFrame();
    }
  }
}

void main() {
  final binding = _WorkspaceTestBinding();
  testWidgets(
    'projects, knowledge imports, source snapshots, history search and pinning',
    (tester) async {
      await I18n.load(AppLanguage.zh);
      final store = ChatStore.instance;
      final db = await store.db;
      // Recover only fixtures whose matching temporary source proves ownership.
      final temporary = await getTemporaryDirectory();
      final recovered = <String>{};
      for (final project in await store.projects()) {
        final match = RegExp(r'^(workspace-qa-[0-9]{16}) (Alpha|Beta)$')
            .firstMatch(project.name);
        if (match == null) {
          continue;
        }
        final oldMarker = match.group(1)!;
        final source = File('${temporary.path}/$oldMarker/cache.md');
        if (!await source.exists() ||
            await source.readAsString() !=
                '缓存有效期为30分钟。Cache expiry is thirty minutes.') {
          continue;
        }
        final oldTopics = (await store.topics())
            .where((t) => t.projectId == project.id)
            .toList();
        if (oldTopics.any(
          (t) => t.model != 'qa-model' || !t.title.startsWith(oldMarker),
        )) {
          continue;
        }
        for (final topic in oldTopics) {
          await db.delete(
            'messages',
            where: 'topic_id = ?',
            whereArgs: [topic.id],
          );
          await db.delete('topics', where: 'id = ?', whereArgs: [topic.id]);
          await store.deleteSetting(memoryCursorSetting(topic.id));
        }
        await store.deleteProject(project.id);
        recovered.add(oldMarker);
      }
      for (final marker in recovered) {
        await Directory('${temporary.path}/$marker').delete(recursive: true);
      }
      final marker = 'workspace-qa-${DateTime.now().microsecondsSinceEpoch}';
      debugPrint('Workspace QA fixture: $marker');
      final root = await Directory(
        '${(await getTemporaryDirectory()).path}/$marker',
      ).create();
      final sourceFile = await File('${root.path}/cache.md')
          .writeAsString('缓存有效期为30分钟。Cache expiry is thirty minutes.');
      final ids = <int>[];
      final topics = <int>[];
      final screenshots = <Map<String, Object>>[];
      binding.reportData = {'screenshots': screenshots};
      final messenger = tester.binding.defaultBinaryMessenger;
      const picker =
          'dev.flutter.pigeon.file_selector_macos.FileSelectorApi.displayOpenPanel';
      messenger.setMockMessageHandler(
        picker,
        (_) async => const StandardMessageCodec().encodeMessage([
          [sourceFile.path],
        ]),
      );
      final boundary = GlobalKey();
      Future<void> show(Widget child, {double width = 1100}) async {
        await tester.binding.setSurfaceSize(Size(width, 760));
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              key: UniqueKey(),
              theme: ThemeData(
                useMaterial3: false,
                brightness: AppPreferences.instance.dark
                    ? Brightness.dark
                    : Brightness.light,
                scaffoldBackgroundColor: IosColors.background,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: IosColors.blue,
                  surface: IosColors.surface,
                  brightness: AppPreferences.instance.dark
                      ? Brightness.dark
                      : Brightness.light,
                ),
              ),
              builder: (context, content) => CupertinoTheme(
                data: CupertinoThemeData(
                  primaryColor: IosColors.blue,
                  brightness: AppPreferences.instance.dark
                      ? Brightness.dark
                      : Brightness.light,
                ),
                child: content!,
              ),
              home: child,
            ),
          ),
        );
        await settle();
      }

      Future<void> capture(String name) async {
        final rendered =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await rendered.toImage(pixelRatio: 1);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        screenshots.add({
          'screenshotName': name,
          'bytes': data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes)
              .toList(),
        });
        image.dispose();
      }

      try {
        ids.add(
          await store.saveProject(
            name: '$marker Alpha',
            instructions: 'Use project facts',
            memory: 'Prefer concise answers',
          ),
        );
        ids.add(await store.saveProject(name: '$marker Beta'));
        for (var i = 0; i < 2; i++) {
          final topic = await db.insert('topics', {
            'title': '$marker chat $i',
            'model': 'qa-model',
            'updated_at': DateTime.now().millisecondsSinceEpoch + i,
            'project_id': ids[i],
          });
          topics.add(topic);
          await store.addMessage(topic, 'user', '$marker 缓存怎么配置？');
        }
        await show(ProjectScreen(project: await store.project(ids.first)));
        final importRow = find.text(T('i18n.knowledge_import'));
        await tester.ensureVisible(importRow);
        await tester.tap(importRow);
        await settle();
        expect(
          (await store.knowledgeDocuments(ids.first)).single.name,
          'cache.md',
        );
        expect(await sourceFile.exists(), isTrue);
        await capture('macos-project-knowledge');
        debugPrint(
          'Workspace QA: native selector import, local persistence and original preservation passed',
        );

        final hits = await store.retrieveKnowledge(ids.first, '缓存有效期');
        expect(hits, isNotEmpty);
        final answer = await store.addMessage(
          topics.first,
          'assistant',
          '30分钟 [${hits.first.label}]',
          knowledgeSources: hits,
        );
        int? selectedTopic;
        int? selectedMessage;
        await show(
          Scaffold(
            body: TopicScreen(
              persistent: true,
              onClose: () {},
              onNew: () {},
              onSettings: () {},
              onChanged: () {},
              onSelect: (_) {},
              onSearchSelect: (topic, message) {
                selectedTopic = topic;
                selectedMessage = message;
              },
            ),
          ),
        );
        await tester.enterText(find.byType(CupertinoSearchTextField), '30分钟');
        await settle();
        expect(find.text('$marker chat 0'), findsOneWidget);
        await capture('macos-project-history-search');
        await tester.tap(find.text('$marker chat 0'));
        expect(selectedTopic, topics.first);
        expect(selectedMessage, answer);
        // Use the actual search clear control, including its focus behavior.
        await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
        await settle();
        expect(
          tester
              .widget<CupertinoSearchTextField>(
                find.byType(CupertinoSearchTextField),
              )
              .controller!
              .text,
          isEmpty,
        );
        await tester.tap(find.text(T('i18n.all_chats')));
        await settle();
        await tester.tap(find.text('$marker Alpha'));
        await settle();
        expect(find.text('$marker chat 0'), findsOneWidget);
        expect(find.text('$marker chat 1'), findsNothing);
        expect(
          tester
              .widget<CupertinoSearchTextField>(
                find.byType(CupertinoSearchTextField),
              )
              .controller!
              .text,
          isEmpty,
        );
        debugPrint('Workspace QA: project filter and search reset passed');
        final row = find.ancestor(
          of: find.text('$marker chat 0'),
          matching: find.byType(IosRow),
        );
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byIcon(CupertinoIcons.ellipsis),
          ),
        );
        await settle();
        await tester.tap(find.text(T('i18n.pin_chat')));
        await settle();
        expect((await store.topics()).first.id, topics.first);
        await capture('macos-project-pinned');
        debugPrint(
          'Workspace QA: scoped history, message location callback and pinning passed',
        );

        await show(
          ProjectScreen(project: await store.project(ids.first)),
          width: 390,
        );
        await capture('compact-project-space');
        await tester.ensureVisible(find.text(T('i18n.knowledge_import')));
        await capture('compact-project-knowledge');
        await show(Scaffold(body: KnowledgeSources(sources: hits)), width: 390);
        await tester.tap(
          find.text(F('i18n.knowledge_sources_count', [hits.length])),
        );
        await settle();
        await tester.tap(find.text('[${hits.first.label}] cache.md'));
        await settle();
        expect(find.text(hits.first.text), findsOneWidget);
        await capture('compact-knowledge-reference');
        debugPrint(
          'Workspace QA: compact project UI and source excerpt navigation passed',
        );

        // Exercise ChatHome's real narrow desktop drawer: it is disposed when
        // opening the project picker, just like the phone drawer.
        const secrets = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        messenger.setMockMethodCallHandler(secrets, (_) async => null);
        await show(const ChatHome(), width: 700);
        final countBefore = (await store.topics()).length;
        Future<void> openDrawer() async {
          await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
          await settle();
        }

        Future<void> chooseFilter(String current, String next) async {
          await tester.tap(find.text(current));
          await settle();
          expect(find.byType(TopicScreen), findsNothing);
          await tester.tap(find.text(next));
          await settle();
        }

        await openDrawer();
        await chooseFilter(T('i18n.all_chats'), '$marker Alpha');
        expect(find.text('$marker chat 0'), findsOneWidget);
        expect(find.text('$marker chat 1'), findsNothing);
        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await settle();
        await openDrawer();
        expect(find.text('$marker Alpha'), findsOneWidget);
        await chooseFilter('$marker Alpha', '$marker Beta');
        expect(find.text('$marker chat 0'), findsNothing);
        expect(find.text('$marker chat 1'), findsOneWidget);
        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await settle();
        final draft = tester
            .widget<ChatComposer>(find.byType(ChatComposer))
            .controller;
        draft.text = 'Draft stays in place';
        await settle();
        Future<void> moreProject(String label, String destination) async {
          await tester.tap(
            find.descendant(
              of: find.byType(ChatMoreButton),
              matching: find.byIcon(CupertinoIcons.ellipsis),
            ),
          );
          await settle();
          await tester.tap(find.text(label));
          await settle();
          await tester.tap(find.text(destination));
          await settle();
        }

        await moreProject(T('i18n.add_to_project'), '$marker Alpha');
        expect(draft.text, 'Draft stays in place');
        expect((await store.topics()).length, countBefore);
        expect(find.text('$marker Alpha'), findsOneWidget);
        await openDrawer();
        expect(find.text('$marker chat 0'), findsOneWidget);
        expect(find.text('$marker chat 1'), findsNothing);
        await tester.tap(find.text('$marker chat 0'));
        await settle();
        await moreProject(T('i18n.move_to_project'), '$marker Beta');
        expect(
          (await store.topics())
              .firstWhere((t) => t.id == topics.first)
              .projectId,
          ids.last,
        );
        await openDrawer();
        expect(find.text('$marker chat 0'), findsOneWidget);
        expect(find.text('$marker chat 1'), findsOneWidget);
        await capture('macos-project-drawer-filter');
        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await settle();
        await tester.binding.setSurfaceSize(const Size(1100, 760));
        await settle();
        await capture('macos-chat-header-alignment');
        await tester.tap(
          find.descendant(
            of: find.byType(ChatMoreButton),
            matching: find.byIcon(CupertinoIcons.ellipsis),
          ),
        );
        await settle();
        expect(find.byType(CupertinoActionSheet), findsNothing);
        expect(
          find.byKey(const ValueKey('desktop-popup-menu')),
          findsOneWidget,
        );
        await capture('macos-chat-more-popover');

        debugPrint(
          'Workspace QA: real drawer recreation, project filters, draft assignment and More move passed',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final topic in topics) {
          await db.delete(
            'messages',
            where: 'topic_id = ?',
            whereArgs: [topic],
          );
          await db.delete('topics', where: 'id = ?', whereArgs: [topic]);
          await store.deleteSetting(memoryCursorSetting(topic));
        }
        for (final id in ids) {
          await store.deleteProject(id);
        }
        messenger.setMockMessageHandler(picker, null);
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
        await root.delete(recursive: true);
        await tester.binding.setSurfaceSize(null);
      }
    },
  );
}

Future<void> settle() async {
  final binding = IntegrationTestWidgetsFlutterBinding.instance;
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await binding.pump(const Duration(milliseconds: 50));
  }
}
