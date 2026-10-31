import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project.dart';

class AgentTask {
  AgentTask({
    required this.providerId,
    required this.model,
    required this.protocol,
    required this.goal,
    required this.systemPrompt,
    this.endpoint = '',
    this.projectId,
    this.topicId,
    this.userMessageId,
    this.providerName,
    this.providerPresetId,
  }) : id = const Uuid().v4(),
       createdAt = DateTime.now().millisecondsSinceEpoch;

  late final String id;
  late final int createdAt;
  final int providerId;
  final String model;
  final ApiProtocol protocol;
  final int? projectId;
  final String goal;
  final String systemPrompt;
  final String endpoint;
  final int? topicId;
  final int? userMessageId;
  final String? providerName;
  final String? providerPresetId;
  int? answerMessageId;
  int? totalMs = 0;
  int contextTokens = 0;
  int contextWindowTokens = 0;
  bool contextCompacted = false;
  bool contextBlocked = false;
  int outputTokenLimit = 0;
  String? finishNotice;
  final requests = <Map<String, dynamic>>[];
  String status = 'paused';
  String answer = '';
  String? error;
  int rounds = 0;
  int calls = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  bool usageComplete = true;
  bool finalReady = false;
  final messages = <Map<String, dynamic>>[];
  final pending = <Map<String, dynamic>>[];
  final steps = <Map<String, dynamic>>[];
  final artifacts = <Map<String, dynamic>>[];
  final sources = <Map<String, dynamic>>[];

  bool get canResume => status != 'completed';

  AgentTask.fromJson(Map<String, dynamic> json)
    : providerId = json['providerId'] as int,
      model = json['model'] as String,
      protocol = ApiProtocol.values.byName(json['protocol'] as String),
      projectId = json['projectId'] as int?,
      goal = json['goal'] as String,
      systemPrompt = json['systemPrompt'] as String,
      endpoint = json['endpoint'] as String? ?? '',
      topicId = json['topicId'] as int?,
      userMessageId = json['userMessageId'] as int?,
      providerName = json['providerName'] as String?,
      providerPresetId = json['providerPresetId'] as String? {
    answerMessageId = json['answerMessageId'] as int?;
    totalMs = json['totalMs'] as int?;
    outputTokenLimit = json['outputTokenLimit'] as int? ?? 0;
    finishNotice = json['finishNotice'] as String?;
    contextTokens = json['contextTokens'] as int? ?? 0;
    contextWindowTokens = json['contextWindowTokens'] as int? ?? 0;
    contextCompacted = json['contextCompacted'] as bool? ?? false;
    contextBlocked = json['contextBlocked'] as bool? ?? false;
    id = json['id'] as String;
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Task ID');
    }
    createdAt = json['createdAt'] as int;
    status = json['status'] as String;
    answer = json['answer'] as String;
    error = json['error'] as String?;
    rounds = json['rounds'] as int;
    calls = json['calls'] as int;
    inputTokens = json['inputTokens'] as int;
    outputTokens = json['outputTokens'] as int;
    usageComplete = json['usageComplete'] as bool;
    finalReady = json['finalReady'] as bool? ?? false;
    for (final entry in {
      'requests': requests,
      'messages': messages,
      'pending': pending,
      'steps': steps,
      'artifacts': artifacts,
      'sources': sources,
    }.entries) {
      entry.value.addAll(
        (json[entry.key] as List? ?? const []).map(
          (v) => Map<String, dynamic>.from(v as Map),
        ),
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt,
    'providerId': providerId,
    'model': model,
    'protocol': protocol.name,
    'projectId': projectId,
    'goal': goal,
    'systemPrompt': systemPrompt,
    'endpoint': endpoint,
    'topicId': topicId,
    'userMessageId': userMessageId,
    'answerMessageId': answerMessageId,
    'totalMs': totalMs,
    'outputTokenLimit': outputTokenLimit,
    'finishNotice': finishNotice,
    'requests': requests,
    'providerName': providerName,
    'providerPresetId': providerPresetId,
    'contextTokens': contextTokens,
    'contextWindowTokens': contextWindowTokens,
    'contextCompacted': contextCompacted,
    'contextBlocked': contextBlocked,
    'status': status,
    'answer': answer,
    'error': error,
    'rounds': rounds,
    'calls': calls,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'usageComplete': usageComplete,
    'finalReady': finalReady,
    'messages': messages,
    'pending': pending,
    'steps': steps,
    'artifacts': artifacts,
    'sources': sources,
  };
}

/// Small task records share settings' existing durable storage and clear action.
class AgentStore {
  AgentStore({ChatStore? store, this.directoryOverride})
    : store = store ?? ChatStore.instance;
  final ChatStore store;
  final Directory? directoryOverride;

  Future<void> save(AgentTask task) async {
    final key = 'agent_task:${task.id}';
    if (task.topicId == null) {
      await store.saveSetting(key, jsonEncode(task.toJson()));
      return;
    }
    final previousAnswerId = task.answerMessageId;
    try {
      await (await store.db).transaction((txn) async {
        final owner = await txn.rawQuery(
          'SELECT t.project_id FROM topics t JOIN messages m ON m.topic_id = t.id WHERE t.id = ? AND m.id = ? AND m.role = ?',
          [task.topicId, task.userMessageId, 'user'],
        );
        if (owner.isEmpty || owner.single['project_id'] != task.projectId) {
          throw StateError('i18n.agent_chat_changed');
        }
        if (task.answerMessageId == null) {
          final previous = await txn.query(
            'settings',
            columns: ['value'],
            where: 'key = ?',
            whereArgs: [key],
          );
          if (previous.isNotEmpty) {
            task.answerMessageId =
                (jsonDecode(previous.single['value'] as String)
                        as Map)['answerMessageId']
                    as int?;
          }
        }
        if (task.answerMessageId == null) {
          final last = await txn.query(
            'messages',
            columns: ['id'],
            where: 'topic_id = ?',
            whereArgs: [task.topicId],
            orderBy: 'id DESC',
            limit: 1,
          );
          if (last.isEmpty || last.single['id'] != task.userMessageId) {
            throw StateError('i18n.agent_chat_changed');
          }
          if (task.status == 'completed') {
            final now = DateTime.now().millisecondsSinceEpoch;
            final sources = task.sources
                .where(
                  (s) =>
                      s['url'] is String &&
                      safeSearchUrl(s['url'] as String) != null,
                )
                .map(
                  (s) => SearchSource(
                    title: s['title'] as String? ?? '',
                    url: s['url'] as String,
                    excerpt: s['excerpt'] as String? ?? '',
                  ),
                )
                .toList();
            task.answerMessageId = await txn.insert('messages', {
              'topic_id': task.topicId,
              'role': 'assistant',
              'content': task.answer,
              'created_at': now,
              'provider_id': task.providerId,
              'provider_name': task.providerName,
              'provider_preset_id': task.providerPresetId,
              'model_id': task.model,
              'total_ms': task.totalMs,
              'input_tokens': task.usageComplete ? task.inputTokens : null,
              'output_tokens': task.usageComplete ? task.outputTokens : null,
              'search_sources': sources.isEmpty
                  ? null
                  : jsonEncode(sources.map((s) => s.toJson()).toList()),
              'knowledge_sources': KnowledgeSource.encode([
                for (final source in task.sources)
                  if (source['documentId'] is int)
                    KnowledgeSource(
                      documentId: source['documentId'] as int,
                      name: source['title'] as String,
                      chunk: source['chunk'] as int? ?? 0,
                      text: source['excerpt'] as String,
                      sourceLabel: source['label'] as String?,
                    ),
              ]),
            });
            await txn.update(
              'topics',
              {'updated_at': now},
              where: 'id = ?',
              whereArgs: [task.topicId],
            );
          }
        }
        await txn.insert('settings', {
          'key': key,
          'value': jsonEncode(task.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } catch (_) {
      task.answerMessageId = previousAnswerId;
      rethrow;
    }
  }

  Future<Map<int, AgentTask>> forTopic(int topicId) async {
    final result = <int, AgentTask>{};
    for (final task in await tasks()) {
      if (task.topicId == topicId && task.userMessageId != null) {
        result.putIfAbsent(task.userMessageId!, () => task);
      }
    }
    return result;
  }

  Future<List<AgentTask>> tasks() async {
    final rows = await (await store.db).query(
      'settings',
      columns: ['value'],
      where: 'key GLOB ?',
      whereArgs: ['agent_task:*'],
    );
    final result = <AgentTask>[];
    for (final row in rows) {
      try {
        result.add(
          AgentTask.fromJson(
            jsonDecode(row['value'] as String) as Map<String, dynamic>,
          ),
        );
      } on FormatException {
        // Leave damaged records untouched so other tasks remain accessible.
      } on TypeError {
        // An incomplete record must not hide the rest of the task history.
      } on ArgumentError {
        // Unknown enum names must not block unrelated chats or task records.
      }
    }
    return result..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Directory> get directory async =>
      directoryOverride ?? await AttachmentStore.instance.agentDirectory;

  Future<File> artifactFile(
    AgentTask task,
    Map<String, dynamic> artifact,
  ) async {
    final file = artifact['file'] as String;
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(task.id) ||
        !RegExp(r'^(report|[0-9]+)\.(md|csv)$').hasMatch(file)) {
      throw const FormatException('Artifact path');
    }
    return File(p.join((await directory).path, task.id, file));
  }

  Future<Map<String, dynamic>> writeArtifact(
    AgentTask task,
    String slot,
    String name,
    String content,
  ) async {
    if (!RegExp(r'^(report|[0-9]+)$').hasMatch(slot) ||
        !RegExp(r'^[^/\\\x00-\x1f]{1,100}\.(md|csv)$').hasMatch(name) ||
        content.trim().isEmpty ||
        utf8.encode(content).length > 120000) {
      throw const FormatException('Artifact content');
    }
    final artifact = <String, dynamic>{
      'name': name,
      'file': '$slot${p.extension(name)}',
    };
    final file = await artifactFile(task, artifact);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      name.endsWith('.csv') ? safeAgentCsv(content) : content,
      flush: true,
    );
    await temporary.rename(file.path);
    task.artifacts.removeWhere((a) => a['file'] == artifact['file']);
    task.artifacts.add(artifact);
    return artifact;
  }

  Future<void> delete(AgentTask task) async {
    final folder = Directory(p.join((await directory).path, task.id));
    if (await folder.exists()) await folder.delete(recursive: true);
    await store.deleteSetting('agent_task:${task.id}');
  }
}

/// Parse quoting before escaping formula cells; commas/newlines inside cells survive.
String safeAgentCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  var closed = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      if (cell.isNotEmpty || closed) throw const FormatException('CSV quote');
      quoted = true;
    } else if (c == ',' || c == '\n' || c == '\r') {
      row.add(cell.toString());
      cell = StringBuffer();
      closed = false;
      if (c != ',') {
        rows.add(row);
        row = [];
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      }
    } else {
      if (closed) throw const FormatException('CSV trailing text');
      cell.write(c);
    }
  }
  if (quoted) throw const FormatException('CSV unclosed quote');
  if (cell.isNotEmpty || closed || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows
      .map(
        (row) => row
            .map((cell) {
              final text =
                  RegExp(r'^[=+@\-]').hasMatch(cell.trimLeft()) ||
                      cell.startsWith('\t')
                  ? "'$cell"
                  : cell;
              return '"${text.replaceAll('"', '""')}"';
            })
            .join(','),
      )
      .join('\r\n');
}
