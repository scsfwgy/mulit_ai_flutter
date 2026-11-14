import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/voice/voice_settings_screen.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  test('DeepSeek key reuse accepts official API variants only', () {
    for (final base in [
      'https://api.deepseek.com',
      'https://api.deepseek.com/v1/',
      'https://api.deepseek.com/anthropic',
      'https://api.deepseek.com.example.org',
      'http://api.deepseek.com',
      'https://api.deepseek.com:8443',
      'https://other.example/v1',
    ]) {
      final provider = ProviderConfig(
        id: 42,
        name: 'DeepSeek',
        baseUrl: base,
        model: 'deepseek-flash',
        protocol: ApiProtocol.anthropic,
      );
      expect(
        canReuseVoiceKey(
          VoiceProtocol.deepseek,
          deepSeekVoiceBaseUrl,
          provider,
        ),
        base == 'https://api.deepseek.com' ||
            base.endsWith('/v1/') ||
            base.endsWith('/anthropic'),
      );
      expect(
        canReuseVoiceKey(
          VoiceProtocol.deepseek,
          'https://other.example/v1',
          provider,
        ),
        false,
      );
    }
  });

  testWidgets(
    'DeepSeek reuses the text key, supports a separate key and keeps edits',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = <String, String>{};
      final secrets = <String, String>{'provider_42': 'fake-text-key'};
      var text = const ProviderConfig(
        id: 42,
        name: 'My DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        protocol: ApiProtocol.openAi,
      );
      const database = MethodChannel('com.tekartik.sqflite');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(database, (call) async {
        if (call.method == 'getDatabasesPath') return '/test';
        if (call.method == 'openDatabase') return 1;
        final args = call.arguments as Map;
        final sql = args['sql'] as String;
        final params = args['arguments'] as List? ?? [];
        if (call.method == 'query') {
          if (sql == 'PRAGMA user_version') {
            return [
              {'user_version': 7},
            ];
          }
          if (sql.contains('FROM providers')) {
            return [
              {...text.toMap(), 'id': 42},
            ];
          }
          return settings.containsKey(params.single)
              ? [
                  {'value': settings[params.single]},
                ]
              : [];
        }
        if (call.method == 'insert') {
          settings[params[0] as String] = params[1] as String;
          return 1;
        }
        if (call.method == 'execute') return null;
        throw StateError('Unexpected database operation: ${call.method}');
      });
      messenger.setMockMethodCallHandler(secure, (call) async {
        final args = call.arguments as Map;
        final key = args['key'] as String;
        switch (call.method) {
          case 'read':
            return secrets[key];
          case 'write':
            secrets[key] = args['value'] as String;
            return null;
          case 'delete':
            secrets.remove(key);
            return null;
          default:
            throw StateError('Unexpected secret operation');
        }
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(database, null);
        messenger.setMockMethodCallHandler(secure, null);
      });
      await tester.pumpWidget(const MaterialApp(home: VoiceSettingsScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(T('i18n.add_voice_provider')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(T('i18n.api_protocol')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DeepSeek'));
      await tester.pumpAndSettle();
      expect(find.text('My DeepSeek'), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsNWidgets(3));
      expect(find.text('https://api.deepseek.com/v1'), findsOneWidget);
      expect(find.text('stella'), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.check_mark));
      await tester.pumpAndSettle();
      expect(find.byType(VoiceServiceEditor), findsNothing);
      final store = ChatStore.instance;
      var voice = (await store.voiceProviders()).single;
      expect(voice.textProviderId, 42);
      expect(voice.protocol, VoiceProtocol.deepseek);
      expect(secrets.keys, ['provider_42']);
      expect(await store.voiceApiKey(voice), 'fake-text-key');
      secrets['provider_42'] = 'fake-updated-text-key';
      expect(await store.voiceApiKey(voice), 'fake-updated-text-key');
      text = const ProviderConfig(
        id: 42,
        name: 'Changed provider',
        baseUrl: 'https://other.example/v1',
        model: 'model',
        protocol: ApiProtocol.openAi,
      );
      expect(await store.voiceApiKey(voice), isNull);

      await tester.tap(find.text('DeepSeek').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(T('i18n.key_source')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(T('i18n.separate_key')));
      await tester.pumpAndSettle();
      final keyField = find.byWidgetPredicate(
        (widget) => widget is CupertinoTextField && widget.obscureText,
      );
      await tester.enterText(keyField, 'fake-separate-key');
      tester.testTextInput.hide();
      await tester.tap(find.byIcon(CupertinoIcons.check_mark));
      await tester.pumpAndSettle();
      voice = (await store.voiceProviders()).single;
      expect(voice.textProviderId, isNull);
      expect(await store.voiceApiKey(voice), 'fake-separate-key');
      expect(jsonEncode(settings), isNot(contains('fake-')));
      await tester.tap(find.text('DeepSeek').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.check_mark));
      await tester.pumpAndSettle();
      expect(
        await store.voiceApiKey((await store.voiceProviders()).single),
        'fake-separate-key',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
