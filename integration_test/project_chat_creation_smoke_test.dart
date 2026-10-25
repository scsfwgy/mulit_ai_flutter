import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/chat/chat_more_menu.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('project selection follows real first sends and all new-chat entries', (
    tester,
  ) async {
    binding.testTextInput.register();
    addTearDown(binding.testTextInput.unregister);
    final factory = databaseFactory;
    final original = await factory.getDatabasesPath();
    final root = await Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        'project-chat-qa-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create();
    // Override only this test engine. Never open the normal app database or Keychain.
    await factory.setDatabasesPath(root.path);
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths =
        'dev.flutter.pigeon.path_provider_foundation.PathProviderApi.getDirectoryPath';
    messenger.setMockMessageHandler(
      paths,
      (_) async => const StandardMessageCodec().encodeMessage([root.path]),
    );
    const secrets = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final keys = <String, String>{};
    messenger.setMockMethodCallHandler(secrets, (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return keys[key];
        case 'write':
          keys[key!] = call.arguments['value'] as String;
          return null;
        case 'delete':
          keys.remove(key);
          return null;
        case 'readAll':
          return keys;
        case 'containsKey':
          return keys.containsKey(key);
        default:
          return null;
      }
    });
    const purchases = MethodChannel('between_models/apple_purchases');
    const companion = MethodChannel('between_models/companion_install');
    const watch = MethodChannel('between_models/watch_updates');
    messenger.setMockMethodCallHandler(
      purchases,
      (_) async => {'enabled': false, 'ready': true},
    );
    messenger.setMockMethodCallHandler(companion, (_) async => null);
    messenger.setMockMethodCallHandler(watch, (_) async => false);
    final store = ChatStore.instance;
    final database = await store.db;
    expect(database.path, p.join(root.path, 'model_chat.db'));
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      final title = body['max_tokens'] == 64;
      if (!title) requests.add(body);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': title ? 'Project QA ${jsonEncode(body['messages']).hashCode}' : 'Project answer ${requests.length}'},
            },
          ],
        })}\n\ndata: [DONE]\n\n',
      );
      await request.response.close();
    });
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 15),
      );
      expect(tester.takeException(), isNull);
    }

    Future<void> drawer() async {
      await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
      await settle();
    }

    Future<void> closeDrawer() async {
      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await settle();
    }

    Future<void> filter(String current, String next) async {
      await drawer();
      await tester.tap(
        find.descendant(
          of: find.byType(TopicScreen),
          matching: find.text(current),
        ),
      );
      await settle();
      await tester.tap(find.text(next));
      await settle();
      expect(find.byType(TopicScreen), findsOneWidget);
      await closeDrawer();
    }

    Future<void> more(String key) async {
      await tester.tap(
        find.descendant(
          of: find.byType(ChatMoreButton),
          matching: find.byIcon(CupertinoIcons.ellipsis),
        ),
      );
      await settle();
      await tester.tap(find.text(T(key)));
      await settle();
    }

    Future<int> send(String text, int? projectId, String? instruction) async {
      final before = (await store.topics()).map((t) => t.id).toSet();
      final count = requests.length;
      await tester.enterText(find.byType(CupertinoTextField).first, text);
      await settle();
      await tester.tap(find.text(T('i18n.send')));
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
        if (requests.length > count &&
            !composer.starting &&
            !composer.sending) {
          break;
        }
      }
      await settle();
      expect(requests.length, count + 1);
      final topic = (await store.topics())
          .where((t) => !before.contains(t.id))
          .single;
      expect(topic.projectId, projectId);
      final messages = await store.messages(topic.id);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.first.content, text);
      final system = (requests.last['messages'] as List)
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'])
          .join('\n');
      if (instruction != null) {
        expect(system, contains(instruction));
      } else {
        expect(system, isNot(contains('QA_ALPHA_INSTRUCTIONS')));
        expect(system, isNot(contains('QA_BETA_INSTRUCTIONS')));
      }
      debugPrint(
        'Project send verified: $text -> project $projectId; native SQLite + HTTP/SSE',
      );
      return topic.id;
    }

    try {
      for (final entry in {
        'search_enabled': '0',
        'voice_auto_read': '0',
        'memory_enabled': '0',
        'app_language': 'zh',
        'app_appearance': 'light',
      }.entries) {
        await store.saveSetting(entry.key, entry.value);
      }
      final provider = await store.saveProvider(
        ProviderConfig(
          id: 0,
          name: 'Project QA service',
          protocol: ApiProtocol.openAi,
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'project-fixture',
        ),
        apiKey: 'fixture-key',
      );
      await store.saveLastChatSelection(
        ChatSelection(provider, 'project-fixture'),
      );
      final alpha = await store.saveProject(
        name: '英语学习',
        instructions: 'QA_ALPHA_INSTRUCTIONS',
      );
      final beta = await store.saveProject(
        name: '工作资料',
        instructions: 'QA_BETA_INSTRUCTIONS',
      );
      await app.main();
      await settle();
      await filter(T('i18n.all_chats'), '英语学习');
      expect(await store.topics(), isEmpty);
      final a1 = await send('QA alpha first', alpha, 'QA_ALPHA_INSTRUCTIONS');
      await more('i18n.new_chat');
      expect(await store.topics(), hasLength(1));
      final a2 = await send('QA alpha second', alpha, 'QA_ALPHA_INSTRUCTIONS');
      await drawer();
      final rows = tester.widgetList<TopicScreen>(find.byType(TopicScreen));
      expect(rows.single.selection!.id, alpha);
      final alphaTopics = (await store.topics())
          .where((t) => t.projectId == alpha)
          .toList();
      expect(alphaTopics, hasLength(2));
      for (final topic in alphaTopics) {
        expect(find.text(topic.title), findsOneWidget);
      }
      await binding.convertFlutterSurfaceToImage();
      await binding.takeScreenshot('ios-project-two-sent-chats');
      await closeDrawer();
      // Selecting another workspace starts its draft; it must not move old history.
      tester.widget<ChatComposer>(find.byType(ChatComposer)).controller.text =
          'preserved draft';
      await settle();
      await filter('英语学习', '工作资料');
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).controller.text,
        'preserved draft',
      );
      expect(await store.topics(), hasLength(2));
      final b1 = await send('QA beta first', beta, 'QA_BETA_INSTRUCTIONS');
      // All is a browsing scope. New chat under All is ungrouped.
      await filter('工作资料', T('i18n.all_chats'));
      await more('i18n.new_chat');
      final ungrouped = await send('QA ungrouped first', null, null);
      await more('i18n.new_chat');
      await more('i18n.add_to_project');
      await tester.tap(find.text('工作资料'));
      await settle();
      final b2 = await send(
        'QA beta assigned draft',
        beta,
        'QA_BETA_INSTRUCTIONS',
      );
      // The drawer pencil is the other new-chat entry.
      await drawer();
      await tester.tap(find.byIcon(CupertinoIcons.square_pencil));
      await settle();
      final b3 = await send('QA beta drawer new', beta, 'QA_BETA_INSTRUCTIONS');
      final ownership = {
        for (final t in await store.topics()) t.id: t.projectId,
      };
      expect(ownership, {
        a1: alpha,
        a2: alpha,
        b1: beta,
        ungrouped: null,
        b2: beta,
        b3: beta,
      });
      await drawer();
      expect(find.text(T('i18n.no_chats_yet')), findsNothing);
      for (final t in await store.topics()) {
        expect(
          find.text(t.title),
          t.projectId == beta ? findsOneWidget : findsNothing,
        );
      }
      debugPrint(
        'Project creation QA: six actual sends, project prompts, two-chat sidebar, draft preservation and original ownership passed',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
      await database.close();
      await factory.setDatabasesPath(original);
      messenger.setMockMessageHandler(paths, null);
      await root.delete(recursive: true);
      for (final channel in [secrets, purchases, companion, watch]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    }
  });
}
