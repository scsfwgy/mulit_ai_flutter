import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/core/sqlite_desktop.dart';

void main() {
  test('legacy reopen followed by upgrade keeps existing projects, documents and chats', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai-link-migration-recovery-',
    );
    final factory = await createDesktopDatabaseFactory(root);
    databaseFactory = factory;
    final path = p.join(await factory.getDatabasesPath(), 'model_chat.db');
    final current = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await createProjectTables(db);
          await db.execute(
            'CREATE TABLE providers(id INTEGER PRIMARY KEY, name TEXT, protocol TEXT, base_url TEXT, model TEXT, preset_id TEXT)',
          );
          await db.execute(
            'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.insert('providers', {
            'id': 1,
            'name': 'Saved provider',
            'protocol': 'openai_chat',
            'base_url': 'https://example.com/v1',
            'model': 'old-model',
          });

          await db.execute(
            'CREATE TABLE topics(id INTEGER PRIMARY KEY, title TEXT, project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL, pinned_at INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE messages(id INTEGER PRIMARY KEY, topic_id INTEGER REFERENCES topics(id), content TEXT, attachments TEXT, knowledge_sources TEXT)',
          );
          await db.execute('CREATE INDEX topics_project ON topics(project_id)');
          await db.insert('projects', {
            'id': 4,
            'name': 'Saved project',
            'instructions': 'Keep instructions',
            'memory': 'Keep project memory',
          });
          await db.insert('knowledge_documents', {
            'id': 8,
            'project_id': 4,
            'name': 'saved.md',
            'content': 'Keep document',
            'characters': 13,
            'bytes': 13,
          });
          await db.insert('knowledge_chunks', {
            'document_id': 8,
            'position': 0,
            'content': 'Keep document',
          });
          await db.insert('topics', {
            'id': 12,
            'title': 'Saved chat',
            'project_id': 4,
            'pinned_at': 123,
          });
          await db.insert('messages', {
            'id': 16,
            'topic_id': 12,
            'content': 'Keep answer',
            'knowledge_sources': '[]',
          });
        },
      ),
    );
    final before = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'providers',
      'settings',
      'projects',
      'knowledge_documents',
      'knowledge_chunks',
      'topics',
      'messages',
    ]) {
      before[table] = await current.query(table);
    }
    await current.close();
    // The installed legacy application has no onDowngrade callback: sqflite
    // sets user_version to 5 while leaving the v7 tables and columns in place.
    final legacy = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 5),
    );
    expect(await legacy.getVersion(), 5);
    expect(await legacy.query('projects'), before['projects']);
    await legacy.close();
    Database? reopened;
    try {
      reopened = await ChatStore.instance.db;
      expect(await reopened.getVersion(), 7);
      for (final entry in before.entries) {
        expect(await reopened.query(entry.key), entry.value, reason: entry.key);
      }
      await ChatStore.instance.saveProvider(
        const ProviderConfig(
          id: 1,
          name: 'Reconnected provider',
          protocol: ApiProtocol.openAi,
          baseUrl: 'https://example.com/v1',
          model: 'new-model',
        ),
      );
      expect((await reopened.query('providers')).single['model'], 'new-model');
    } finally {
      await reopened?.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'partial project schema is completed once without replacing existing rows',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ai-link-partial-schema-',
      );
      final factory = await createDesktopDatabaseFactory(root);
      final path = p.join(await factory.getDatabasesPath(), 'partial.db');
      final partial = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute(
              "CREATE TABLE projects(id INTEGER PRIMARY KEY, name TEXT NOT NULL, instructions TEXT NOT NULL DEFAULT '', memory TEXT NOT NULL DEFAULT '')",
            );
            await db.execute(
              'CREATE TABLE topics(id INTEGER PRIMARY KEY, title TEXT, project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL)',
            );
            await db.execute(
              'CREATE TABLE messages(id INTEGER PRIMARY KEY, topic_id INTEGER REFERENCES topics(id), content TEXT)',
            );
            await db.insert('projects', {
              'id': 5,
              'name': 'Existing partial project',
              'instructions': 'Do not replace',
              'memory': 'Do not remove',
            });
            await db.insert('topics', {
              'id': 9,
              'title': 'Existing chat',
              'project_id': 5,
            });
            await db.insert('messages', {
              'id': 13,
              'topic_id': 9,
              'content': 'Existing message',
            });
          },
        ),
      );
      await partial.close();
      final repaired = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, _, _) => ensureProjectSchema(db),
        ),
      );
      try {
        for (var i = 0; i < 2; i++) {
          await repaired.transaction((txn) => ensureProjectSchema(txn));
        }
        expect(await repaired.getVersion(), 7);
        expect(
          (await repaired.query('projects')).single['memory'],
          'Do not remove',
        );
        expect(
          (await repaired.query('projects')).single['instructions'],
          'Do not replace',
        );
        expect((await repaired.query('topics')).single['project_id'], 5);
        expect((await repaired.query('topics')).single['pinned_at'], 0);
        expect(
          (await repaired.query('messages')).single['content'],
          'Existing message',
        );
        expect(
          (await repaired.query('messages')).single['knowledge_sources'],
          isNull,
        );
        expect(
          (await repaired.rawQuery('PRAGMA table_info(topics)'))
              .where((r) => r['name'] == 'project_id'),
          hasLength(1),
        );
        expect(
          (await repaired.rawQuery('PRAGMA index_list(topics)'))
              .where((r) => r['name'] == 'topics_project'),
          hasLength(1),
        );
        await repaired.insert('knowledge_documents', {
          'id': 7,
          'project_id': 5,
          'name': 'new.txt',
          'content': 'text',
          'characters': 4,
          'bytes': 4,
        });
        await repaired.insert('knowledge_chunks', {
          'document_id': 7,
          'position': 0,
          'content': 'text',
        });
        await repaired.delete('projects', where: 'id = ?', whereArgs: [5]);
        expect((await repaired.query('topics')).single['project_id'], isNull);
        expect(await repaired.query('knowledge_documents'), isEmpty);
        expect(await repaired.query('knowledge_chunks'), isEmpty);
        expect(
          (await repaired.query('messages')).single['content'],
          'Existing message',
        );
      } finally {
        await repaired.close();
        await root.delete(recursive: true);
      }
    },
  );
}
