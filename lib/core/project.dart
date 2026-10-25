import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class ChatProject {
  const ChatProject({
    required this.id,
    required this.name,
    this.instructions = '',
    this.memory = '',
  });
  final int id;
  final String name;
  final String instructions;
  final String memory;

  factory ChatProject.fromMap(Map<String, Object?> row) => ChatProject(
    id: row['id'] as int,
    name: row['name'] as String,
    instructions: row['instructions'] as String,
    memory: row['memory'] as String,
  );
}

class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.name,
    required this.characters,
  });
  final int id;
  final String name;
  final int characters;
}

/// Persist the exact supplied excerpt so a citation remains readable after edits.
class KnowledgeSource {
  const KnowledgeSource({
    required this.documentId,
    required this.name,
    required this.chunk,
    required this.text,
  });
  final int documentId;
  final String name;
  final int chunk;
  final String text;
  String get label => 'K$documentId-${chunk + 1}';
  Map<String, Object> toJson() => {
    'documentId': documentId,
    'name': name,
    'chunk': chunk,
    'text': text,
  };
  static String? encode(List<KnowledgeSource> sources) => sources.isEmpty
      ? null
      : jsonEncode(sources.map((s) => s.toJson()).toList());
  static List<KnowledgeSource> decode(String? value) => value == null
      ? []
      : (jsonDecode(value) as List)
            .map(
              (s) => KnowledgeSource(
                documentId: s['documentId'] as int,
                name: s['name'] as String,
                chunk: s['chunk'] as int,
                text: s['text'] as String,
              ),
            )
            .toList();
}

Future<void> createProjectTables(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    instructions TEXT NOT NULL DEFAULT '',
    memory TEXT NOT NULL DEFAULT ''
  )''');
  await db.execute('''CREATE TABLE knowledge_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    content TEXT NOT NULL,
    characters INTEGER NOT NULL,
    bytes INTEGER NOT NULL
  )''');
  await db.execute('''CREATE TABLE knowledge_chunks (
    document_id INTEGER NOT NULL REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    content TEXT NOT NULL,
    PRIMARY KEY(document_id, position)
  )''');
  await db.execute(
    'CREATE INDEX knowledge_project ON knowledge_documents(project_id)',
  );
}
