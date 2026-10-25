import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/chat/chat_message_meta.dart';
import 'package:mulit_ai_flutter/provider/provider_badge.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;
  final values = <String, String>{};
  const channel = MethodChannel('com.tekartik.sqflite');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDatabasesPath') return '/test';
      if (call.method == 'openDatabase') return 1;
      final args = Map<String, Object?>.from(call.arguments as Map);
      if (call.method == 'execute') {
        return (args['sql'] as String).startsWith('BEGIN')
            ? {'transactionId': 1}
            : null;
      }
      if (call.method == 'query') {
        if ((args['sql'] as String).startsWith('PRAGMA table_info(')) {
          return <Map<String, Object?>>[];
        }
        if (args['sql'] == 'PRAGMA user_version') {
          return [
            {'user_version': 4},
          ];
        }
        final key = (args['arguments'] as List).single;
        return values.containsKey(key)
            ? [
                {'value': values[key]},
              ]
            : [];
      }
      if (call.method == 'insert') {
        final row = args['arguments'] as List;
        values[row[0] as String] = row[1] as String;
        return 1;
      }
      throw StateError('Unexpected operation: ${call.method}');
    });
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(channel, null));
  setUp(() async {
    values.clear();
    await AppPreferences.instance.load();
  });

  Widget message({
    SpeechPlaybackState state = SpeechPlaybackState.idle,
    VoidCallback? speak,
  }) => MaterialApp(
    home: Scaffold(
      body: ChatMessageMeta(
        assistant: true,
        content: 'hello',
        providerName: 'Provider',
        modelId: 'model',
        onCopy: () {},
        onSpeak: speak,
        speechState: state,
      ),
    ),
  );

  testWidgets(
    'provider follows model switch; copy and speech hide independently',
    (tester) async {
      final prefs = AppPreferences.instance;
      await prefs.setChatInfoVisible(ChatInfoField.modelId, false);
      await tester.pumpWidget(message(speak: () {}));
      expect(find.byType(ProviderBadge), findsNothing);
      expect(find.text('model'), findsNothing);
      expect(find.byIcon(CupertinoIcons.doc_on_doc), findsOneWidget);
      expect(find.byType(SpeechPlaybackIndicator), findsOneWidget);
      await prefs.setChatInfoVisible(ChatInfoField.copy, false);
      await tester.pumpWidget(message(speak: () {}));
      expect(find.byIcon(CupertinoIcons.doc_on_doc), findsNothing);
      expect(find.byType(SpeechPlaybackIndicator), findsOneWidget);
      await prefs.setChatInfoVisible(ChatInfoField.speech, false);
      await tester.pumpWidget(message(speak: () {}));
      expect(find.byType(SpeechPlaybackIndicator), findsNothing);
    },
  );

  testWidgets('simple mode hides the complete row and restores saved choices', (
    tester,
  ) async {
    final prefs = AppPreferences.instance;
    await prefs.setChatInfoVisible(ChatInfoField.copy, false);
    await prefs.setAutoReadReplies(true);
    await prefs.setSimpleMessageInfo(true);
    await prefs.load();
    expect(prefs.autoReadReplies, true);
    expect(
      ChatInfoField.values.every((field) => !prefs.showChatInfo(field)),
      true,
    );
    await tester.pumpWidget(message(speak: () {}));
    expect(find.byType(Wrap), findsNothing);
    await prefs.setSimpleMessageInfo(false);
    await prefs.load();
    await tester.pumpWidget(message(speak: () {}));
    expect(find.text('Provider'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.doc_on_doc), findsNothing);
    expect(find.byType(SpeechPlaybackIndicator), findsOneWidget);
  });

  testWidgets(
    'missing speech callback hides icon; loading blocks taps; playback animates',
    (tester) async {
      await tester.pumpWidget(message());
      expect(find.byType(SpeechPlaybackIndicator), findsNothing);
      var taps = 0;
      await tester.pumpWidget(
        message(state: SpeechPlaybackState.loading, speak: () => taps++),
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await tester.tap(find.byType(SpeechPlaybackIndicator));
      expect(taps, 0);
      await tester.pumpWidget(
        message(state: SpeechPlaybackState.playing, speak: () => taps++),
      );
      final fade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(SpeechPlaybackIndicator),
          matching: find.byType(FadeTransition),
        ),
      );
      final initial = fade.opacity.value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(fade.opacity.value, isNot(initial));
      await tester.tap(find.byType(SpeechPlaybackIndicator));
      expect(taps, 1);
      await tester.pumpWidget(message(speak: () => taps++));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
