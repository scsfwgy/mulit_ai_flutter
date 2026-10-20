import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/watch/watch_chat.dart';
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
      final providers = <Map<String, Object?>>[];
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
          if (sql.contains('FROM providers')) return providers;
          if (sql.contains('FROM model_prompts')) return [];
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
        if (call.method == 'update' || call.method == 'delete') {
          if (sql.contains('DELETE FROM providers')) {
            providers.removeWhere((item) => item['id'] == params.single);
          }
          if (sql.contains('DELETE FROM settings')) values.remove(params.single);
          return 1;
        }
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
        service: SearchService.deepseek,
        endpoint: 'https://api.deepseek.com/v1/tools/search',
      );
      await store.saveSearchProvider(original, apiKey: 'fake-search-secret');
      expect(
        statements,
        contains('ALTER TABLE messages ADD COLUMN search_sources TEXT'),
      );
      expect((await store.selectedSearchProvider())!.id, 'test');
      expect(
        (await store.selectedSearchProvider())!.service,
        SearchService.deepseek,
      );
      expect(await store.searchApiKey(original), 'fake-search-secret');
      expect(jsonEncode(values), isNot(contains('fake-search-secret')));
      await store.saveSearchProvider(original, apiKey: '');
      expect(await store.searchApiKey(original), 'fake-search-secret');
      const changed = SearchProviderConfig(
        id: 'test',
        name: 'Search',
        service: SearchService.tavily,
        endpoint: 'https://proxy.example.com/search',
      );
      await expectLater(store.saveSearchProvider(changed), throwsFormatException);
      expect((await store.selectedSearchProvider())!.endpoint, original.endpoint);
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
      expect(await store.searchApiKey(original), isNull);
      expect(await store.selectedSearchProvider(), isNull);
      expect(values['search_enabled'], '0');
      expect(
        (await store.messages(7)).single.searchSources.single.url,
        'https://example.com/source',
      );

      values.remove('search_provider_id');
      const text = ProviderConfig(
        id: 42,
        name: 'My DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        model: 'deepseek-flash',
        protocol: ApiProtocol.openAi,
      );
      providers.add({...text.toMap(), 'id': text.id});
      secrets['provider_42'] = 'text-key';
      final linked = (await store.selectedSearchProvider())!;
      expect(linked.textProviderId, 42);
      expect(linked.name, 'My DeepSeek');
      expect(await store.searchApiKey(linked), 'text-key');
      expect(values['search_providers'], '[]');
      expect(secrets.keys, isNot(contains('search_${linked.id}')));
      values['search_provider_id'] = '';
      expect(
        await store.selectedSearchProvider(),
        isNull,
        reason: 'Explicit none stays disabled',
      );
      values['search_provider_id'] = linked.id;

      // Saving search options stores only the source ID, never a copy of its key.
      await store.saveSearchProvider(linked);
      expect((await store.searchProviders()).length, 1);
      expect((await store.selectedSearchProvider())!.textProviderId, 42);
      expect(values['search_providers'], contains('textProviderId'));
      expect(jsonEncode(values), isNot(contains('text-key')));
      expect(secrets.keys, isNot(contains('search_${linked.id}')));
      var changes = 0;
      final subscription = store.watchConfigurationChanges.listen(
        (_) => changes++,
      );
      addTearDown(subscription.cancel);
      await store.saveProvider(text, apiKey: 'rotated-key');
      await Future<void>.delayed(Duration.zero);
      expect(changes, greaterThan(0));
      expect(await store.searchApiKey(linked), 'rotated-key');
      values['search_enabled'] = '1';
      final processor = WatchChatProcessor(store: store);
      final snapshot = await processor.configuration();
      expect(snapshot['searchReady'], true);
      expect((snapshot['search'] as Map)['apiKey'], 'rotated-key');
      expect(
        jsonEncode(await processor.preferences()),
        isNot(contains('rotated-key')),
      );
      secrets.remove('provider_42');
      expect(await store.searchApiKey(linked), isNull);
      await expectLater(store.saveSearchProvider(linked), throwsFormatException);
      secrets['provider_42'] = 'rotated-key';
      for (final endpoint in [
        'https://api.deepseek.com.evil.test',
        'https://other.example.com',
        'http://api.deepseek.com',
      ]) {
        providers[0] = {...text.toMap(), 'id': 42, 'base_url': endpoint};
        expect(await store.searchApiKey(linked), isNull, reason: endpoint);
      }
      providers[0] = {...text.toMap(), 'id': 42};
      final wrongEndpoint = SearchProviderConfig(
        id: linked.id,
        name: linked.name,
        service: SearchService.deepseek,
        endpoint: 'https://other.example.com/search',
        textProviderId: 42,
      );
      expect(await store.searchApiKey(wrongEndpoint), isNull);
      await expectLater(
        store.saveSearchProvider(wrongEndpoint),
        throwsFormatException,
      );
      await store.deleteProvider(42);
      expect(await store.searchProviders(), isEmpty);
      expect(await store.selectedSearchProvider(), isNull);
      expect(await store.searchApiKey(linked), isNull);
      expect(values['search_enabled'], '0');
      expect((await processor.configuration())['searchReady'], false);
      expect(secrets, isEmpty);
      // An automatically selected source has no saved search/default row yet.
      values.remove('search_provider_id');
      values['search_enabled'] = '1';
      providers.add({...text.toMap(), 'id': 99});
      secrets['provider_99'] = 'unsaved-source-key';
      expect((await store.selectedSearchProvider())!.textProviderId, 99);
      await store.deleteProvider(99);
      expect(await store.searchProviders(), isEmpty);
      expect(values['search_enabled'], '0');
      expect(secrets, isEmpty);
    },
  );
}
