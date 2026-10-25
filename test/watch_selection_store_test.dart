import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  test(
    'phone switches replace an explicit watch model without creating a topic',
    () async {
      final values = <String, String>{
        'watch_provider_id': '1',
        'watch_model_id': 'old-model',
        'last_chat_selection': const ChatSelection(
          2,
          'deepseek-flash',
        ).toJson(),
        'watch_topic_id': '42',
      };
      var transactionActive = false;
      const channel = MethodChannel('com.tekartik.sqflite');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getDatabasesPath') return '/test';
        if (call.method == 'openDatabase') return 1;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final sql = args['sql'] as String;
        if (call.method == 'execute') {
          if (sql.startsWith('BEGIN')) {
            transactionActive = true;
            return {'transactionId': 1};
          }
          if (sql == 'COMMIT') {
            transactionActive = false;
          }
          return null;
        }
        if (call.method == 'query') {
          if ((sql).startsWith('PRAGMA table_info(')) {
            return <Map<String, Object?>>[];
          }
          if (sql == 'PRAGMA user_version') {
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
          expect(transactionActive, true);
          expect(sql, startsWith('INSERT OR REPLACE INTO settings'));
          final row = args['arguments'] as List;
          values[row[0] as String] = row[1] as String;
          return 1;
        }
        throw StateError('Unexpected database operation: ${call.method}');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final store = ChatStore.instance;
      expect((await loadWatchChatSelection(store))?.model, 'deepseek-flash');

      await store.saveWatchChatSelection(const ChatSelection(1, 'watch-only'));
      expect((await loadWatchChatSelection(store))?.model, 'watch-only');
      expect((await store.lastChatSelection())?.model, 'deepseek-flash');
      expect(values['watch_topic_id'], '');

      await store.saveLastChatSelection(
        const ChatSelection(2, 'custom/model-id'),
      );
      expect((await loadWatchChatSelection(store))?.providerId, 2);
      expect((await loadWatchChatSelection(store))?.model, 'custom/model-id');
      expect((await store.lastChatSelection())?.model, 'custom/model-id');

      await store.saveLastChatSelection(const ChatSelection(2, 'new-model'));
      expect((await loadWatchChatSelection(store))?.model, 'new-model');
      expect(values['watch_topic_id'], '');
    },
  );
}
