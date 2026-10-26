import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_home.dart';
import 'package:mulit_ai_flutter/chat/incoming_share.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

import 'sqflite_stub.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useSqflitePluginFactory();
  late Directory root;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('share-ui-');
  });
  tearDownAll(() async {
    await root.delete(recursive: true);
  });

  testWidgets(
    'cold and warm shares wait for consent, stay drafts and do not duplicate',
    (tester) async {
      installEmptyDatabaseStub();
      final registered = <String>[];
      void mock(String name, Future<Object?> Function(MethodCall) handler) {
        registered.add(name);
        messenger.setMockMethodCallHandler(MethodChannel(name), handler);
      }

      for (final channel in [
        'xyz.luan/audioplayers.global',
        'xyz.luan/audioplayers.global/events',
        'com.llfbandit.record/messages',
        'between_models/companion_install',
        'between_models/watch_updates',
        'plugins.it_nomads.com/flutter_secure_storage',
        'plugins.flutter.io/image_picker',
      ]) {
        mock(channel, (_) async => null);
      }
      mock('xyz.luan/audioplayers', (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          mock('xyz.luan/audioplayers/events/$id', (_) async => null);
        }
        return null;
      });
      mock('plugins.flutter.io/path_provider', (_) async => root.path);
      final source = await tester.runAsync(
        () => File('${root.path}/quote.txt').writeAsString('Shared source'),
      );
      var pending = true;
      var id = 'cold';
      var acknowledgements = 0;
      mock(IncomingShare.channel.name, (call) async {
        if (call.method == 'peek') {
          return pending
              ? {
                  'id': id,
                  'files': [
                    {'path': source!.path, 'name': 'quote.txt'},
                  ],
                }
              : null;
        }
        if (call.method == 'ack') {
          acknowledgements++;
          pending = false;
        }
        return null;
      });
      addTearDown(() {
        for (final name in registered) {
          messenger.setMockMethodCallHandler(MethodChannel(name), null);
        }
      });
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const MaterialApp(home: ChatHome()));
      Future<void> drain() async {
        for (var i = 0; i < 50; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await drain();
      ChatComposer composer() =>
          tester.widget<ChatComposer>(find.byType(ChatComposer));
      expect(composer().attachments.single.name, 'quote.txt');
      expect(composer().controller.text, isEmpty);
      expect(acknowledgements, 1);
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byType(CupertinoTextField).last,
        'Keep my question',
      );
      id = 'warm';
      pending = true;
      Future<void> changed() async {
        unawaited(
          messenger.handlePlatformMessage(
            IncomingShare.channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('changed'),
            ),
            (_) {},
          ),
        );
        await tester.pump();
      }

      await changed();
      await drain();
      expect(find.text(T('i18n.share_received')), findsOneWidget);
      await tester.tap(find.text(T('i18n.share_later')));
      await drain();
      expect(composer().controller.text, 'Keep my question');
      expect(pending, isTrue);
      expect(acknowledgements, 1);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drain();
      await tester.tap(find.text(T('i18n.share_open')));
      await drain();
      expect(composer().controller.text, isEmpty);
      expect(composer().attachments, hasLength(1));
      expect(acknowledgements, 2);
      await changed();
      await drain();
      expect(acknowledgements, 2);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      unawaited(
        messenger.handlePlatformMessage(
          IncomingShare.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('failed'),
          ),
          (_) {},
        ),
      );
      await tester.pump();
      expect(find.text(T('i18n.share_import_failed')), findsOneWidget);
      expect(composer().attachments, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await drain();
      expect(tester.takeException(), isNull);
    },
  );
}
