import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;
  test('watch history is acknowledged once, ordered, and restores after phone reset', () async {
    final settings = <String, String>{};
    final topics = <Map<String, Object?>>[];
    final messages = <Map<String, Object?>>[];
    var transaction = false;
    const channel = MethodChannel('com.tekartik.sqflite');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDatabasesPath') return '/test-watch-sync';
      if (call.method == 'openDatabase') return 1;
      final args = Map<String, Object?>.from(call.arguments as Map);
      final sql = args['sql'] as String;
      final values = args['arguments'] as List? ?? [];
      if (call.method == 'execute') {
        if (sql.startsWith('BEGIN')) {
          transaction = true;
          return {'transactionId': 1};
        }
        if (sql == 'COMMIT' || sql == 'ROLLBACK') {
          transaction = false;
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
        if (sql.contains('FROM settings')) {
          final value = settings[values.single];
          return value == null
              ? []
              : [
                  {'value': value},
                ];
        }
        if (sql.contains('FROM providers')) {
          return [
            {'id': 7},
          ];
        }
        if (sql.contains('FROM topics')) {
          return topics.where((t) => t['id'] == values.single).toList();
        }
      }
      if (call.method == 'insert') {
        expect(transaction, true);
        final columns = RegExp(r'\((.*?)\) VALUES')
            .firstMatch(sql)!
            .group(1)!
            .split(',')
            .map((c) => c.trim().replaceAll('"', ''));
        final placeholders = RegExp(r'VALUES \((.*?)\)')
            .firstMatch(sql)!
            .group(1)!
            .split(',');
        var index = 0;
        final row = Map<String, Object?>.fromIterables(
          columns,
          placeholders.map((p) => p.trim() == '?' ? values[index++] : null),
        );
        if (sql.contains('INTO settings')) {
          settings[row['key'] as String] = row['value'] as String;
          return 1;
        }
        if (sql.contains('INTO topics')) {
          final id = topics.length + 1;
          topics.add({...row, 'id': id});
          return id;
        }
        if (sql.contains('INTO messages')) {
          messages.add(row);
          return messages.length;
        }
      }
      if (call.method == 'update') return 1;
      throw StateError('Unexpected sync operation: ${call.method} $sql');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    Map<String, dynamic> turn(int sequence, {bool apple = true}) => {
      'id': '00000000-0000-0000-0000-${sequence.toString().padLeft(12, '0')}',
      'conversationId': '11111111-1111-1111-1111-111111111111',
      'sequence': sequence,
      'createdAt': 123,
      'providerId': 7,
      'providerName': 'Test',
      'model': 'chat',
      'transcript': 'q$sequence',
      'answer': 'a$sequence',
      if (apple) 'source': 'apple-watch',
    };
    final store = ChatStore.instance;
    await store.saveWatchTurn(turn(0));
    await store.saveWatchTurn(turn(0));
    expect(messages.length, 2);
    expect(topics.length, 1);
    await expectLater(store.saveWatchTurn(turn(2)), throwsStateError);
    expect(messages.length, 2);
    await store.saveWatchTurn(turn(1));
    expect(messages.length, 4);
    expect(topics.length, 1);
    expect(
      settings['watch_sequence_11111111-1111-1111-1111-111111111111'],
      '2',
    );
    // Starting a topic on either watch keeps the old phone history intact.
    for (final apple in [true, false]) {
      final conversationId = apple
          ? '22222222-2222-2222-2222-222222222222'
          : '33333333-3333-3333-3333-333333333333';
      final first = {
        ...turn(0, apple: apple),
        'id': conversationId,
        'conversationId': conversationId,
      };
      await store.saveWatchTurn(first);
      await store.saveWatchTurn(first);
      expect(settings['watch_sequence_$conversationId'], '1');
    }
    expect(
      settings.keys.where((key) => key.startsWith('watch_search_topic_')),
      isEmpty,
    );
    await store.saveWatchTurn({...turn(2), 'searchUsed': true});
    expect(settings['watch_search_topic_1'], '1');
    expect(topics.length, 3);
    expect(messages.length, 10);
    expect(messages.take(4).map((m) => m['content']), ['q0', 'a0', 'q1', 'a1']);
    // Only mock test data is cleared, never a simulator or device database.
    settings.clear();
    topics.clear();
    messages.clear();
    await expectLater(
      store.saveWatchTurn(turn(3, apple: false)),
      throwsStateError,
    );
    await store.saveWatchTurn(turn(3));
    await store.saveWatchTurn(turn(4));
    await store.saveWatchTurn(turn(3));
    expect(messages.length, 4);
    expect(topics.length, 1);
    expect(
      settings['watch_sequence_11111111-1111-1111-1111-111111111111'],
      '5',
    );
  });
}
