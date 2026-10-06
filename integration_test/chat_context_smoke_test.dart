import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mulit_ai_flutter/chat_context.dart';
import 'package:mulit_ai_flutter/chat_context_screen.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/main.dart' as app;

/// Real SQLite and secure-storage integration against a local HTTP fixture.
/// Restore preferences and remove only this test's provider and conversation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'context error can be adjusted and retried without duplicating the user message',
    (tester) async {
      // Exercise chat behavior on Apple simulators without StoreKit purchases.
      const purchases = MethodChannel('between_models/apple_purchases');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        purchases,
        (_) async => {'enabled': false, 'ready': true},
      );
      final store = ChatStore.instance;
      final database = await store.db;
      final saved = <String, String?>{};
      for (final key in [
        'last_chat_selection',
        'search_enabled',
        'voice_auto_read',
        'app_language',
        'global_prompt',
        ChatContext.settingKey,
      ]) {
        saved[key] = await store.setting(key);
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        request.response.bufferOutput = false;
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        if (requests.length == 1) {
          request.response.statusCode = 400;
          request.response.write(
            '{"error":{"code":"context_length_exceeded","message":"too large"}}',
          );
        } else {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          for (final text in ['Context ', '**retry** works.']) {
            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': text},
                  },
                ],
              })}\n\n',
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          request.response.write('data: [DONE]\n\n');
        }
        await request.response.close();
      });
      int? providerId;
      int? topicId;
      try {
        await store.saveSetting('search_enabled', '0');
        await store.saveSetting('voice_auto_read', '0');
        await store.saveSetting('app_language', 'zh');
        await store.saveSetting('global_prompt', '');
        await store.saveSetting(ChatContext.settingKey, '32768');
        providerId = await store.saveProvider(
          ProviderConfig(
            id: 0,
            name: 'Context integration fixture',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'local-context-test',
            protocol: ApiProtocol.openAi,
          ),
          apiKey: 'temporary-local-key',
        );
        final provider = (await store.providers()).firstWhere(
          (p) => p.id == providerId,
        );
        topicId = await store.createTopicWithMessage(
          provider,
          provider.model,
          'Old context fixture',
        );
        await store.addMessage(
          topicId,
          'assistant',
          '文' * 10000,
          modelId: provider.model,
          provider: provider,
        );
        await store.updateTopic(topicId, title: 'Context integration fixture');
        await store.saveLastChatSelection(
          ChatSelection(provider.id, provider.model),
        );
        app.main();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Context integration fixture'));
        await tester.pumpAndSettle();
        final input = find.byType(CupertinoTextField).first;
        await tester.enterText(input, 'Latest context question');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (find.text('调整上下文').evaluate().isNotEmpty) break;
        }
        await tester.pumpAndSettle();
        expect(find.text(ChatContext.serverLimitMessage), findsOneWidget);
        expect(requests, hasLength(1));
        expect(requests.first['messages'], hasLength(3));
        await binding.convertFlutterSurfaceToImage();
        await binding.takeScreenshot('android-context-limit');
        await tester.tap(find.text('调整上下文'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatContextScreen), findsOneWidget);
        await tester.tap(find.text('8K Token'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(CupertinoIcons.back));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重试回复'));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (requests.length == 2 &&
              find.byIcon(CupertinoIcons.stop_fill).evaluate().isEmpty) {
            break;
          }
        }
        await tester.pumpAndSettle();
        expect(requests, hasLength(2));
        expect(requests.last['messages'], [
          {'role': 'user', 'content': 'Latest context question'},
        ]);
        final stored = await store.messages(topicId);
        expect(stored, hasLength(4));
        expect(
          stored.where((m) => m.content == 'Latest context question'),
          hasLength(1),
        );
        expect(stored[1].content.length, 10000);
        expect(stored.last.content, 'Context **retry** works.');
        expect(find.text(ChatContext.serverLimitMessage), findsNothing);
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot('android-context-retry');
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (topicId != null) await store.deleteTopic(topicId);
        if (providerId != null) await store.deleteProvider(providerId);
        for (final entry in saved.entries) {
          if (entry.value == null) {
            await database.delete(
              'settings',
              where: 'key = ?',
              whereArgs: [entry.key],
            );
          } else {
            await store.saveSetting(entry.key, entry.value!);
          }
        }
        await server.close(force: true);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          purchases,
          null,
        );
      }
    },
  );
}
