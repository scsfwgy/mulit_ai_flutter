import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;
  const channel = MethodChannel('com.tekartik.sqflite');
  final settings = <String, String>{};
  var failSave = false;

  setUp(() {
    failSave = false;
    settings.clear();
    AppPreferences.instance.language = AppLanguage.zh;
    AppPreferences.instance.contextWindowTokens =
        ChatContext.defaultWindowTokens;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getDatabasesPath') return '/test-context';
          if (call.method == 'openDatabase') return 1;
          final args = Map<String, Object?>.from(call.arguments as Map);
          final sql = args['sql'] as String? ?? '';
          final params = args['arguments'] as List? ?? [];
          if (call.method == 'execute') return null;
          if (call.method == 'query') {
            if (sql == 'PRAGMA user_version') {
              return [
                {'user_version': 5},
              ];
            }
            final key = params.single as String;
            return settings.containsKey(key)
                ? [
                    {'value': settings[key]},
                  ]
                : [];
          }
          if (call.method == 'insert') {
            if (failSave) throw PlatformException(code: 'test-save-failure');
            settings[params[0] as String] = params[1] as String;
            return 1;
          }
          throw StateError('Unexpected database operation ${call.method}');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AppPreferences.instance.language = AppLanguage.zh;
    AppPreferences.instance.contextWindowTokens =
        ChatContext.defaultWindowTokens;
  });

  testWidgets('budget selection persists and reloads after preferences reset', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChatContextScreen()));
    await tester.tap(find.text('16K Token'));
    await tester.pumpAndSettle();
    expect(settings[ChatContext.settingKey], '16384');
    expect(AppPreferences.instance.contextWindowTokens, 16384);
    AppPreferences.instance.contextWindowTokens = 32768;
    await AppPreferences.instance.load();
    expect(AppPreferences.instance.contextWindowTokens, 16384);
    expect(find.byIcon(CupertinoIcons.check_mark), findsOneWidget);
  });

  testWidgets(
    'save failure leaves the current budget and shows an English error',
    (tester) async {
      AppPreferences.instance.language = AppLanguage.en;
      failSave = true;
      await tester.pumpWidget(const MaterialApp(home: ChatContextScreen()));
      await tester.tap(find.text('8K Token'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save context settings. Please try again.'),
        findsOneWidget,
      );
      expect(AppPreferences.instance.contextWindowTokens, 32768);
      expect(settings, isEmpty);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    },
  );
}
