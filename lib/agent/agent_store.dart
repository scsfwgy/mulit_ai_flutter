import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/data.dart';

class AgentTask {
  AgentTask({
    required this.providerId,
    required this.model,
    required this.protocol,
    required this.goal,
    required this.systemPrompt,
    this.endpoint = '',
    this.projectId,
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

  bool get canResume =>
      status != 'completed' &&
      (finalReady || (pending.isNotEmpty ? calls < 24 : rounds < 12));

  AgentTask.fromJson(Map<String, dynamic> json)
    : providerId = json['providerId'] as int,
      model = json['model'] as String,
      protocol = ApiProtocol.values.byName(json['protocol'] as String),
      projectId = json['projectId'] as int?,
      goal = json['goal'] as String,
      systemPrompt = json['systemPrompt'] as String,
      endpoint = json['endpoint'] as String? ?? '' {
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
      'messages': messages,
      'pending': pending,
      'steps': steps,
      'artifacts': artifacts,
      'sources': sources,
    }.entries) {
      entry.value.addAll(
        (json[entry.key] as List).map(
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

  Future<void> save(AgentTask task) =>
      store.saveSetting('agent_task:${task.id}', jsonEncode(task.toJson()));

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
