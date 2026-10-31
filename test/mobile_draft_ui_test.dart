import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_home.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/chat_draft.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';

import 'sqflite_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useSqflitePluginFactory);
  testWidgets(
    'switching mobile chats and new draft restores separate compositions',
    (tester) async {
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('mobile-drafts-ui-'),
      );
      addTearDown(() => root!.delete(recursive: true));
      installEmptyDatabaseStub(
        providers: [
          {
            'id': 1,
            'name': 'Fixture',
            'base_url': 'https://example.com/v1',
            'model': 'test',
            'protocol': 'openai_chat',
          },
        ],
        topics: [
          for (var i = 1; i <= 2; i++)
            {
              'id': i,
              'title': 'Chat $i',
              'provider_id': 1,
              'model': 'test',
              'updated_at': i,
            },
        ],
        messages: [
          for (var i = 1; i <= 2; i++)
            {
              'id': i,
              'topic_id': i,
              'role': 'user',
              'content': 'Original $i',
              'created_at': i,
            },
        ],
      );
      AppPreferences.instance.agentEnabled = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final channels = <String>[];
      void mock(String name, Future<Object?> Function(MethodCall) handler) {
        channels.add(name);
        messenger.setMockMethodCallHandler(MethodChannel(name), handler);
      }

      for (final channel in [
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers.global/events',
        'com.llfbandit.record/messages',
        'between_models/companion_install',
        'between_models/watch_updates',
        'between_models/incoming_share',
        'plugins.it_nomads.com/flutter_secure_storage',
        'plugins.flutter.io/image_picker',
      ]) {
        mock(channel, (_) async => null);
      }
      mock('xyz.luan/audioplayers', (call) async {
        if (call.method == 'create') {
          mock(
            'xyz.luan/audioplayers/events/${(call.arguments as Map)['playerId']}',
            (_) async => null,
          );
        }
        return null;
      });
      mock('plugins.flutter.io/path_provider', (_) async => root!.path);
      addTearDown(() {
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(MethodChannel(channel), null);
        }
      });
      final attachment = await tester.runAsync(() async {
        final source = await File('${root!.path}/source.txt')
            .writeAsString('Draft file contents');
        return AttachmentStore.instance.importFile(source.path, '材料.txt');
      });
      await ChatStore.instance.saveSetting(
        chatDraftKey(),
        ChatDraft(text: 'New draft', attachments: [attachment!]).encode(),
      );
      await tester.pumpWidget(const MaterialApp(home: ChatHome()));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(ChatComposer).evaluate().isNotEmpty &&
            tester
                .widget<ChatComposer>(find.byType(ChatComposer))
                .inputEnabled) {
          break;
        }
      }
      await tester.pumpAndSettle();
      Finder input() => find.descendant(
        of: find.byType(ChatComposer),
        matching: find.byType(CupertinoTextField),
      );
      Future<void> choose(String title) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      expect(find.text('材料.txt'), findsOneWidget);
      await choose('Chat 1');
      expect(
        tester.widget<CupertinoTextField>(input()).controller!.text,
        isEmpty,
      );
      expect(find.text('材料.txt'), findsNothing);
      await tester.enterText(input(), 'Draft A');
      await choose('Chat 2');
      expect(
        tester.widget<CupertinoTextField>(input()).controller!.text,
        isEmpty,
      );
      await tester.enterText(input(), 'Draft B');
      await choose('Chat 1');
      expect(
        tester.widget<CupertinoTextField>(input()).controller!.text,
        'Draft A',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.square_pencil));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(input()).controller!.text,
        'New draft',
      );
      expect(find.text('材料.txt'), findsOneWidget);
      expect(
        ChatDraft.decode(
          await ChatStore.instance.setting(chatDraftKey(topicId: 2)),
        ).text,
        'Draft B',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
