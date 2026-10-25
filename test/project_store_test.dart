import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/core/sqlite_desktop.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';

void main() {
  late Directory temporary;
  late ChatStore store;
  late Database database;
  const provider = ProviderConfig(
    id: 1,
    name: 'Test',
    protocol: ApiProtocol.openAi,
    baseUrl: 'https://example.com/v1',
    model: 'model',
  );

  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('ai-link-projects-');
    final factory = await createDesktopDatabaseFactory(temporary);
    databaseFactory = factory;
    final path = p.join(await factory.getDatabasesPath(), 'model_chat.db');
    // A real v6 database, including a saved conversation and provider.
    final old = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE providers(id INTEGER PRIMARY KEY, name TEXT, protocol TEXT, base_url TEXT, model TEXT, preset_id TEXT)',
          );
          await db.execute(
            'CREATE TABLE topics(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, provider_id INTEGER, model TEXT NOT NULL, updated_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT, topic_id INTEGER NOT NULL REFERENCES topics(id) ON DELETE CASCADE, role TEXT, content TEXT, created_at INTEGER, provider_id INTEGER, provider_name TEXT, provider_preset_id TEXT, model_id TEXT, first_token_ms INTEGER, total_ms INTEGER, input_tokens INTEGER, output_tokens INTEGER, search_sources TEXT, attachments TEXT)',
          );
          await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE model_prompts(provider_id INTEGER, model TEXT, prompt TEXT)',
          );
          await db.insert('topics', {
            'id': 1,
            'title': 'Existing history',
            'model': 'model',
            'updated_at': 1,
          });
          await db.insert('messages', {
            'topic_id': 1,
            'role': 'user',
            'content': 'keep original history',
            'created_at': 1,
          });
        },
      ),
    );
    await old.close();
    store = ChatStore.instance;
    database = await store.db;
  });
  tearDownAll(() async {
    await database.close();
    await temporary.delete(recursive: true);
  });

  test(
    'v6 upgrade preserves messages and defaults while adding project schema',
    () async {
      expect(await database.getVersion(), 7);
      final topic = (await store.topics()).single;
      expect(topic.projectId, isNull);
      expect(topic.pinnedAt, 0);
      expect((await store.messages(1)).single.content, 'keep original history');
      expect(await store.projects(), isEmpty);
    },
  );

  test('project prompts and knowledge stay isolated; deleting a project keeps chats', () async {
    final first = await store.saveProject(
      name: 'Alpha',
      instructions: 'Alpha instructions',
      memory: 'Alpha facts',
    );
    final second = await store.saveProject(
      name: 'Beta',
      instructions: 'Beta instructions',
      memory: 'Beta facts',
    );
    final topic = await store.createTopicWithMessage(
      provider,
      'model',
      '如何配置缓存？',
      projectId: first,
    );
    final other = await store.createTopicWithMessage(
      provider,
      'model',
      'cache setting',
      projectId: second,
    );
    await store.saveSetting('global_prompt', 'Global prompt');
    await store.saveSetting(memoryEnabledSetting, '1');
    await store.saveSetting(memoryInGlobalPromptSetting, '1');
    await store.saveMemoryProfile('Global private facts');
    final prompt = await store.chatSystemPrompt(1, 'model', topicId: topic);
    expect(prompt, contains('Global prompt'));
    expect(prompt, contains('Alpha instructions'));
    expect(prompt, contains('Alpha facts'));
    expect(prompt, isNot(contains('Beta')));
    expect(prompt, isNot(contains('Global private facts')));
    expect(await store.chatUsesMemory(topic), isFalse);
    expect(
      await store.saveMergedMemory(
        revision: await store.memoryRevision(),
        profile: 'leaked project',
        topicId: topic,
        cursorMessageId: 3,
      ),
      isFalse,
    );
    expect(
      await store.chatSystemPrompt(1, 'model', projectId: second),
      contains('Beta instructions'),
    );
    expect(
      await store.chatSystemPrompt(1, 'model'),
      contains('Global private facts'),
    );

    final doc = await store.addKnowledge(
      first,
      '缓存说明.md',
      '缓存有效期为30分钟。cache expires after thirty minutes.',
    );
    await store.addKnowledge(
      second,
      'secret.md',
      '缓存有效期为999小时。cache expires after 999 hours.',
    );
    final sources = await store.retrieveKnowledge(first, '缓存有效期多久 cache?');
    expect(sources, hasLength(1));
    expect(sources.single.documentId, doc);
    expect(knowledgeContext(sources), contains('30分钟'));
    expect(knowledgeContext(sources), isNot(contains('999')));
    expect(await store.retrieveKnowledge(first, 'unrelatedword'), isEmpty);
    final answerId = await store.addMessage(
      topic,
      'assistant',
      '30分钟 [${sources.single.label}]',
      knowledgeSources: sources,
    );
    final saved = (await store.messages(topic))
        .firstWhere((m) => m.id == answerId);
    expect(saved.knowledgeSources.single.text, sources.single.text);

    await store.moveTopic(topic, null);
    expect(await store.memoryCursor(topic), answerId);
    await store.moveTopic(topic, first);
    await store.deleteProject(first);
    final ungrouped = (await store.topics()).firstWhere((t) => t.id == topic);
    expect(ungrouped.projectId, isNull);
    expect(
      (await store.messages(topic)).last.knowledgeSources.single.name,
      '缓存说明.md',
    );
    expect(await store.knowledgeDocuments(first), isEmpty);
    expect(
      await database.rawQuery(
        'SELECT * FROM knowledge_chunks WHERE document_id = ?',
        [doc],
      ),
      isEmpty,
    );
    expect(
      (await store.topics()).firstWhere((t) => t.id == other).projectId,
      second,
    );
    await store.deleteProject(second);
  });

  test('literal history search, scope, pinning, and cursor do not rewrite messages', () async {
    final project = await store.saveProject(name: 'Search project');
    final topic = await store.createTopicWithMessage(
      provider,
      'model',
      'literal 100% under_score back\\slash',
      projectId: project,
    );
    final newest = await store.createTopicWithMessage(
      provider,
      'model',
      'Other data',
    );
    await store.updateTopic(topic, title: 'needle title');
    await store.addMessage(topic, 'assistant', 'history keyword needle');
    await store.addMessage(topic, 'user', 'unrelated body');
    final percent = await store.searchHistory('100%');
    expect(percent.map((m) => m.topic.id), [topic]);
    expect(percent.single.messageId, isNotNull);
    expect(await store.searchHistory('_score'), hasLength(1));
    expect(await store.searchHistory('back\\slash'), hasLength(1));
    expect(await store.searchHistory("' OR 1=1 --"), isEmpty);
    expect(await store.searchHistory('needle title'), hasLength(1));
    expect(await store.searchHistory('needle', projectId: project), isNotEmpty);
    expect(await store.searchHistory('needle', ungrouped: true), isEmpty);
    expect(
      await store.searchHistory('keyword', projectId: project + 999),
      isEmpty,
    );
    await store.pinTopic(topic, true);
    expect((await store.topics()).first.id, topic);
    final count = (await store.messages(topic)).length;
    await store.pinTopic(topic, false);
    await store.moveTopic(topic, null);
    expect((await store.messages(topic)).length, count);
    expect((await store.topics()).any((t) => t.id == newest), isTrue);
    await store.deleteProject(project);
  });

  test(
    'knowledge bounds, Chinese retrieval, unicode chunks, and source snapshots',
    () async {
      final project = await store.saveProject(name: 'Knowledge bounds');
      await expectLater(
        store.addKnowledge(project, 'a', ''),
        throwsFormatException,
      );
      await expectLater(
        store.addKnowledge(project, 'a', 'a' * 200001),
        throwsFormatException,
      );
      await expectLater(
        store.addKnowledge(project, 'a', 'binary\x00payload'),
        throwsFormatException,
      );
      await expectLater(
        store.addKnowledge(project + 999, 'a', 'content'),
        throwsA(anything),
      );
      final body = '🔎长文' * 300 + '缓存配置：默认三十分钟。';
      await store.addKnowledge(project, 'long.md', body);
      final hits = await store.retrieveKnowledge(
        project,
        '缓存配置',
        tokenBudget: 1600,
      );
      expect(hits, isNotEmpty);
      expect(hits.any((s) => s.text.contains('三十分钟')), isTrue);
      expect(
        hits.fold<int>(
          0,
          (n, s) =>
              n +
              ChatContext.estimateTokens(s.text) +
              ChatContext.estimateTokens(s.name) +
              64,
        ),
        lessThanOrEqualTo(1600),
      );
      final chunks = knowledgeChunks('😀' * 1500);
      expect(chunks.every((c) => c.runes.every((r) => r == 0x1f600)), isTrue);
      expect(
        knowledgeTerms('缓存配置 Cache TTL'),
        containsAll(['缓存', '存配', '配置', 'cache', 'ttl']),
      );
      final restored = KnowledgeSource.decode(KnowledgeSource.encode(hits));
      expect(restored.first.text, hits.first.text);
      for (var i = 0; i < 49; i++) {
        await store.addKnowledge(project, 'doc$i', 'Small document');
      }
      await expectLater(
        store.addKnowledge(project, 'overflow', 'data'),
        throwsFormatException,
      );
      await store.deleteProject(project);
    },
  );
}
