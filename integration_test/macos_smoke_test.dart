import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/chat/desktop_chat.dart';
import 'package:mulit_ai_flutter/main.dart' as app;
import 'package:mulit_ai_flutter/chat/message_copy.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';

/// Run on macOS with real SQLite, Keychain, network and clipboard plugins.
/// Only the provider/topics created here are removed; existing data is kept.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Mac native storage and streamed chat smoke test', (
    tester,
  ) async {
    final store = ChatStore.instance;
    debugPrint('Mac smoke: opening local database');
    final database = await store.db;
    debugPrint('Mac smoke: reading saved preferences');
    final savedSelection = await store.setting('last_chat_selection');
    final savedSearch = await store.setting('search_enabled');
    final savedAutoRead = await store.setting('voice_auto_read');
    debugPrint('Mac smoke: saving clipboard text');
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    debugPrint('Mac smoke: starting local HTTP fixture');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var streamRequests = 0;
    var titleRequests = 0;
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (body['stream'] == true) {
        final titleRequest = body['max_tokens'] == 64;
        if (titleRequest) {
          titleRequests++;
        } else {
          streamRequests++;
        }
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        for (final chunk
            in titleRequest
                ? ['Mac smoke test']
                : ['Mac ', '**streaming** works.']) {
          request.response.write(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': chunk},
                },
              ],
            })}\n\n',
          );
          await request.response.flush();
        }
        request.response.write('data: [DONE]\n\n');
      } else {
        titleRequests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Mac smoke test'},
              },
            ],
          }),
        );
      }
      await request.response.close();
    });
    int? providerId;
    try {
      debugPrint('Mac smoke: saving fixture provider and Keychain entry');
      providerId = await store.saveProvider(
        ProviderConfig(
          id: 0,
          name: 'Mac local smoke test',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'local-test-model',
          protocol: ApiProtocol.openAi,
        ),
        apiKey: 'local-test-only',
      );
      expect(await store.apiKey(providerId), 'local-test-only');
      debugPrint('Mac smoke: launching app with fixture selection');
      // A second plugin read checks actual Keychain persistence, not UI state.
      await store.saveLastChatSelection(
        ChatSelection(providerId, 'local-test-model'),
      );
      await store.saveSetting('search_enabled', '0');
      await store.saveSetting('voice_auto_read', '0');
      app.main();
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(CupertinoTextField).evaluate().isNotEmpty && i > 20) {
          break;
        }
      }
      expect(find.text('无法打开本地数据'), findsNothing);
      expect(find.byType(TopicScreen), findsOneWidget);
      expect(find.byType(DesktopNavigationMenu), findsNothing);
      final editor = find.byType(CupertinoTextField).first;
      await tester.tap(editor);
      await tester.enterText(editor, 'Mac local test');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (titleRequests > 0 &&
            find.text('Mac smoke test').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(streamRequests, 1);
      expect(titleRequests, 1);
      final topics = (await store.topics())
          .where((t) => t.providerId == providerId)
          .toList();
      expect(topics, hasLength(1));
      final messages = await store.messages(topics.single.id);
      expect(messages.map((m) => m.content).toList(), [
        'Mac local test',
        'Mac **streaming** works.',
      ]);
      await copyMessage('**Mac clipboard**', MessageCopyFormat.formatted);
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        'Mac clipboard',
      );
      await tester.enterText(editor, 'desktop draft preserved');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('手表'), findsNothing);
      expect(find.byType(DesktopNavigationMenu), findsOneWidget);
      expect(find.byType(TopicScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('desktop-section-providers')));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      await tester.tap(find.text('Mac local smoke test'));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderEditor), findsOneWidget);
      expect(find.byType(DesktopNavigationMenu), findsOneWidget);
      expect(find.byType(TopicScreen), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(ProviderEditor),
          matching: find.byIcon(CupertinoIcons.back),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProviderEditor), findsNothing);
      expect(find.byType(ProviderScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('desktop-section-chat')));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderScreen), findsNothing);
      expect(find.byType(TopicScreen), findsOneWidget);
      expect(find.byType(DesktopNavigationMenu), findsNothing);
      expect(
        tester.widget<CupertinoTextField>(editor).controller?.text,
        'desktop draft preserved',
      );
      expect(streamRequests, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      if (providerId != null) {
        for (final topic in (await store.topics()).where(
          (t) => t.providerId == providerId,
        )) {
          await store.deleteTopic(topic.id);
        }
        await store.deleteProvider(providerId);
      }
      for (final entry in {
        'last_chat_selection': savedSelection,
        'search_enabled': savedSearch,
        'voice_auto_read': savedAutoRead,
      }.entries) {
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
      if (clipboard != null) await Clipboard.setData(clipboard);
      await server.close(force: true);
    }
  });
}
