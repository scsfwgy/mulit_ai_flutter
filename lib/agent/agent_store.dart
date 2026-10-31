import 'dart:convert';
import 'dart:io';

import 'package:mulit_ai_flutter/agent/agent_artifact_format.dart';
import 'package:crypto/crypto.dart';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

/// Knowledge notes contain text sources, independently of the delivered format.
String agentNoteName(String title, {bool table = false}) {
  final stem = title
      .trim()
      .replaceFirst(
        RegExp(r'\.(?:pdf|docx?|xlsx?|md|csv|txt)$', caseSensitive: false),
        '',
      )
      .trim();
  return stem.isEmpty ? '' : '$stem.${table ? 'csv' : 'md'}';
}

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
  String? errorCode;
  int rounds = 0;
  int calls = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  bool usageComplete = true;
  bool finalReady = false;
  final instructions = <String>[];
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
    errorCode = json['errorCode'] as String?;
    rounds = json['rounds'] as int;
    calls = json['calls'] as int;
    inputTokens = json['inputTokens'] as int;
    outputTokens = json['outputTokens'] as int;
    usageComplete = json['usageComplete'] as bool;
    finalReady = json['finalReady'] as bool? ?? false;
    instructions.addAll(
      (json['instructions'] as List? ?? const []).cast<String>(),
    );
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
    'errorCode': errorCode,
    'rounds': rounds,
    'calls': calls,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'usageComplete': usageComplete,
    'finalReady': finalReady,
    'instructions': instructions,
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

  Future<void> save(AgentTask task, {AgentTask? expected}) async {
    final key = 'agent_task:${task.id}';
    Future<void> checkCurrent(DatabaseExecutor txn) async {
      if (expected == null) return;
      final rows = await txn.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
      );
      if (rows.isEmpty) throw StateError('i18n.agent_chat_changed');
      final current = AgentTask.fromJson(
        jsonDecode(rows.single['value'] as String) as Map<String, dynamic>,
      );
      if (!current.canResume ||
          jsonEncode(current.toJson()) != jsonEncode(expected.toJson())) {
        throw StateError('i18n.agent_chat_changed');
      }
    }

    if (task.topicId == null) {
      if (expected == null) {
        await store.saveSetting(key, jsonEncode(task.toJson()));
      } else {
        await (await store.db).transaction((txn) async {
          await checkCurrent(txn);
          await txn.insert('settings', {
            'key': key,
            'value': jsonEncode(task.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        });
      }
      return;
    }
    final previousAnswerId = task.answerMessageId;
    try {
      await (await store.db).transaction((txn) async {
        await checkCurrent(txn);
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
        !RegExp(r'^(report|[0-9]+)\.(md|csv|pdf|docx|xlsx)$').hasMatch(file)) {
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
    final format = AgentArtifactFormat.forName(name);
    if (format == null ||
        name.length > 105 ||
        !RegExp(r'^(report|[0-9]+)$').hasMatch(slot) ||
        name.contains(String.fromCharCode(92)) ||
        name.contains(RegExp(r'[\/\x00-\x1f<>:"|?*]')) ||
        p.basenameWithoutExtension(name).trim().isEmpty) {
      throw const FormatException('Artifact content');
    }
    final bytes = await encodeAgentArtifact(format, content);
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Artifact size');
    }
    final digest = sha256
        .convert(utf8.encode(content))
        .toString()
        .substring(0, 32);
    final source = '$slot-$digest.${format.table ? 'csv' : 'md'}';
    final artifact = <String, dynamic>{
      'name': name,
      'file': '$slot.${format.extension}',
      'source': source,
    };
    final file = await artifactFile(task, artifact);
    await file.parent.create(recursive: true);
    final sourceFile = File(p.join(file.parent.path, source));
    if (!await sourceFile.exists()) {
      final sourceTemporary = File('${sourceFile.path}.tmp');
      await sourceTemporary.writeAsString(content, flush: true);
      await sourceTemporary.rename(sourceFile.path);
    }
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    task.artifacts.removeWhere((a) => a['file'] == artifact['file']);
    task.artifacts.add(artifact);
    return artifact;
  }

  Future<({String content, bool table})> artifactSource(
    AgentTask task,
    Map<String, dynamic> artifact,
  ) async {
    final file = await artifactFile(task, artifact);
    final source = artifact['source'];
    File readable = file;
    if (source != null) {
      if (source is! String ||
          !RegExp(r'^(report|[0-9]+)-[a-f0-9]{32}\.(md|csv)$')
              .hasMatch(source)) {
        throw const FormatException('Artifact source');
      }
      readable = File(p.join(file.parent.path, source));
    } else if (AgentArtifactFormat.forName(artifact['name'] as String)
            ?.binary !=
        false) {
      throw const FormatException('Artifact source unavailable');
    }
    if (await readable.length() > 120000) {
      throw const FormatException('Artifact source size');
    }
    return (
      content: await readable.readAsString(),
      table: readable.path.endsWith('.csv'),
    );
  }

  Future<void> refine(AgentTask task, String instruction) async {
    final text = instruction.trim();
    if (!task.canResume ||
        text.isEmpty ||
        text.length > 4000 ||
        task.instructions.fold(0, (n, s) => n + s.length) + text.length >
            20000) {
      throw FormatException(T('i18n.agent_instruction_limit'));
    }
    void apply(AgentTask target) {
      for (final pending in target.pending) {
        final call = ModelToolCall.fromJson(pending);
        final result = {
          'code': 'task_updated',
          'error': 'Not executed: the user added new requirements. Reconsider tools using the updated instructions.',
        };
        target.steps[pending['step'] as int]
          ..['status'] = 'skipped'
          ..['result'] = result;
        appendModelToolResult(
          target.messages,
          target.protocol,
          call,
          jsonEncode(result),
        );
      }
      target.pending.clear();
      target.instructions.add(text);
      if (target.messages.isEmpty) {
        target.messages.add({'role': 'user', 'content': target.goal});
      }
      target.messages.add({'role': 'user', 'content': text});
      target.status = 'paused';
      target.answer = '';
      target.error = null;
      target.errorCode = null;
      target.finalReady = false;
      target.finishNotice = null;
      target.contextBlocked = false;
    }

    final updated = AgentTask.fromJson(
      jsonDecode(jsonEncode(task.toJson())) as Map<String, dynamic>,
    );
    apply(updated);
    await save(updated, expected: task);
    apply(task);
  }

  Future<({int id, bool created})> saveProjectNote(
    AgentTask task,
    int projectId,
    String title,
    String content, {
    String sourceKey = 'answer',
  }) async {
    if (sourceKey != 'answer' &&
        !RegExp(r'^(report|[0-9]+)\.(md|csv|pdf|docx|xlsx)$')
            .hasMatch(sourceKey)) {
      throw const FormatException('Note source');
    }
    final table = AgentArtifactFormat.forName(sourceKey)?.table ?? false;
    final noteName = agentNoteName(title, table: table);
    return (await store.db).transaction((txn) async {
      if ((await txn.query(
        'projects',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [projectId],
      )).isEmpty) {
        throw FormatException(T('i18n.knowledge_invalid'));
      }
      final key = 'agent_note:${task.id}:$sourceKey:$projectId';
      final marker = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      final previous = marker.isEmpty
          ? null
          : int.tryParse(marker.first['value'] as String);
      final existing = previous == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'knowledge_documents',
              columns: ['id', 'name'],
              where: 'id = ? AND project_id = ?',
              whereArgs: [previous, projectId],
            );
      if (existing.isNotEmpty) {
        final oldName = existing.single['name'] as String;
        final corrected = agentNoteName(oldName, table: table);
        if (corrected != oldName && corrected.isNotEmpty) {
          await txn.update(
            'knowledge_documents',
            {'name': corrected},
            where: 'id = ?',
            whereArgs: [previous],
          );
        }
        return (id: previous!, created: false);
      }
      final id = await insertProjectKnowledge(
        txn,
        projectId,
        noteName,
        content,
      );
      await txn.insert('settings', {
        'key': key,
        'value': '$id',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return (id: id, created: true);
    });
  }

  Future<void> delete(AgentTask task) async {
    final folder = Directory(p.join((await directory).path, task.id));
    if (await folder.exists()) await folder.delete(recursive: true);
    await (await store.db).transaction((txn) async {
      await txn.delete(
        'settings',
        where: 'key = ?',
        whereArgs: ['agent_task:${task.id}'],
      );
      await txn.delete(
        'settings',
        where: 'key GLOB ?',
        whereArgs: ['agent_note:${task.id}:*'],
      );
    });
  }
}
