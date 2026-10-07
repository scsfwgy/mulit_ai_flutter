import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  test(
    'v4 upgrade, secure search keys and persisted sources survive edits',
    () async {
      final values = <String, String>{};
      final secrets = <String, String>{};
      final messages = <Map<String, Object?>>[];
      final statements = <String>[];
      const databaseChannel = MethodChannel('com.tekartik.sqflite');
      const secureChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(secureChannel, (call) async {
        final args = Map<String, Object?>.from(call.arguments as Map);
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return secrets[key];
          case 'write':
            secrets[key!] = args['value'] as String;
            return null;
          case 'delete':
            secrets.remove(key);
            return null;
          default:
            throw StateError('Unexpected secure operation: ${call.method}');
        }
      });
      messenger.setMockMethodCallHandler(databaseChannel, (call) async {
        if (call.method == 'getDatabasesPath') return '/test';
        if (call.method == 'openDatabase') return 1;
        final args = Map<String, Object?>.from(call.arguments as Map);
        final sql = args['sql'] as String;
        final params = args['arguments'] as List? ?? [];
        if (call.method == 'execute') {
          statements.add(sql);
          if (sql.startsWith('BEGIN')) return {'transactionId': 1};
          return null;
        }
        if (call.method == 'query') {
          if (sql == 'PRAGMA user_version') {
            return [
              {'user_version': 4},
            ];
          }
          if (sql.contains('FROM messages')) return messages;
          final key = params.single;
          return values.containsKey(key)
              ? [
                  {'value': values[key]},
                ]
              : [];
        }
        if (call.method == 'insert') {
          if (sql.contains('INTO settings')) {
            values[params[0] as String] = params[1] as String;
            return 1;
          }
          final columns = sql
              .substring(sql.indexOf('(') + 1, sql.indexOf(')'))
              .split(',')
              .map((s) => s.trim());
          final expressions = sql
              .substring(sql.indexOf('VALUES (') + 8, sql.lastIndexOf(')'))
              .split(',')
              .map((s) => s.trim())
              .toList();
          final row = <String, Object?>{'id': messages.length + 1};
          var index = 0;
          var columnIndex = 0;
          for (final column in columns) {
            row[column] = expressions[columnIndex++] == '?'
                ? params[index++]
                : null;
          }
          messages.add(row);
          return row['id'];
        }
        if (call.method == 'update') return 1;
        throw StateError('Unexpected database operation: ${call.method}');
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(databaseChannel, null);
        messenger.setMockMethodCallHandler(secureChannel, null);
      });
      final store = ChatStore.instance;
      const original = SearchProviderConfig(
        id: 'test',
        name: 'Search',
        service: SearchService.tavily,
        endpoint: 'https://api.tavily.com/search',
      );
      await store.saveSearchProvider(original, apiKey: 'fake-search-secret');
      expect(
        statements,
        contains('ALTER TABLE messages ADD COLUMN search_sources TEXT'),
      );
      expect((await store.selectedSearchProvider())!.id, 'test');
      expect(await store.searchApiKey('test'), 'fake-search-secret');
      expect(jsonEncode(values), isNot(contains('fake-search-secret')));
      await store.saveSearchProvider(original, apiKey: '');
      expect(await store.searchApiKey('test'), 'fake-search-secret');
      const changed = SearchProviderConfig(
        id: 'test',
        name: 'Search',
        service: SearchService.tavily,
        endpoint: 'https://proxy.example.com/search',
      );
      await expectLater(
        store.saveSearchProvider(changed),
        throwsFormatException,
      );
      expect(
        (await store.selectedSearchProvider())!.endpoint,
        original.endpoint,
      );
      await store.addMessage(
        7,
        'assistant',
        'answer',
        searchSources: [
          const SearchSource(
            title: 'Source',
            url: 'https://example.com/source',
            excerpt: 'Evidence',
          ),
        ],
      );
      final loaded = (await store.messages(7)).single;
      expect(loaded.searchSources.single.excerpt, 'Evidence');
      final legacy = Map<String, Object?>.from(messages.single)
        ..remove('search_sources');
      expect(ChatMessage.fromMap(legacy).searchSources, isEmpty);
      await store.deleteSearchProvider('test');
      expect(await store.searchApiKey('test'), isNull);
      expect(await store.selectedSearchProvider(), isNull);
      expect(values['search_enabled'], '0');
      expect(
        (await store.messages(7)).single.searchSources.single.url,
        'https://example.com/source',
      );
    },
  );
}
