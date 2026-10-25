import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Darwin repairs retained v7 tables after legacy reopen and saves provider',
    (tester) async {
      final factory = databaseFactory;
      final original = await factory.getDatabasesPath();
      final temporary = await getTemporaryDirectory();
      final root = await Directory(
        p.join(
          temporary.path,
          'database-recovery-qa-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create();
      final path = p.join(root.path, 'model_chat.db');
      Database? opened;
      try {
        // All native database calls in this engine point at our private fixture.
        // No normal application database or secure-storage key is read or changed.
        await factory.setDatabasesPath(root.path);
        final seeded = await factory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 7,
            onCreate: (db, _) async {
              await createProjectTables(db);
              await db.execute(
                'CREATE TABLE providers(id INTEGER PRIMARY KEY, name TEXT, protocol TEXT, base_url TEXT, model TEXT, preset_id TEXT)',
              );
              await db.execute(
                'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
              );
              await db.execute(
                'CREATE TABLE topics(id INTEGER PRIMARY KEY, title TEXT, project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL, pinned_at INTEGER NOT NULL DEFAULT 0)',
              );
              await db.execute(
                'CREATE TABLE messages(id INTEGER PRIMARY KEY, topic_id INTEGER, content TEXT, knowledge_sources TEXT)',
              );
              await db.execute(
                'CREATE INDEX topics_project ON topics(project_id)',
              );
              await db.insert('providers', {
                'id': 1,
                'name': 'Saved provider',
                'protocol': 'openai_chat',
                'base_url': 'https://example.com/v1',
                'model': 'old-model',
              });
              await db.insert('settings', {
                'key': 'app_language',
                'value': 'en',
              });
              await db.insert('projects', {
                'id': 2,
                'name': 'Saved project',
                'instructions': 'Keep instructions',
                'memory': 'Keep memory',
              });
              await db.insert('knowledge_documents', {
                'id': 3,
                'project_id': 2,
                'name': 'saved.md',
                'content': 'Keep text',
                'characters': 9,
                'bytes': 9,
              });
              await db.insert('knowledge_chunks', {
                'document_id': 3,
                'position': 0,
                'content': 'Keep text',
              });
              await db.insert('topics', {
                'id': 4,
                'title': 'Saved chat',
                'project_id': 2,
                'pinned_at': 17,
              });
              await db.insert('messages', {
                'id': 5,
                'topic_id': 4,
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
          before[table] = await seeded.query(table);
        }
        await seeded.close();
        final legacy = await factory.openDatabase(
          path,
          options: OpenDatabaseOptions(version: 6),
        );
        expect(await legacy.getVersion(), 6);
        await legacy.close();
        opened = await ChatStore.instance.db;
        expect(opened.path, path);
        expect(await opened.getVersion(), 7);
        for (final entry in before.entries) {
          expect(await opened.query(entry.key), entry.value, reason: entry.key);
        }
        await ChatStore.instance.saveProvider(
          const ProviderConfig(
            id: 1,
            name: 'Saved provider',
            protocol: ApiProtocol.openAi,
            baseUrl: 'https://example.com/v1',
            model: 'new-model',
          ),
        );
        expect((await opened.query('providers')).single['model'], 'new-model');
        expect(
          (await opened.query('messages')).single['content'],
          'Keep answer',
        );
        expect(
          (await opened.query('projects')).single['memory'],
          'Keep memory',
        );
      } finally {
        await opened?.close();
        await factory.setDatabasesPath(original);
        await root.delete(recursive: true);
      }
    },
  );
}
