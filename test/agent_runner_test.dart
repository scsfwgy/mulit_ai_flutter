import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/core/sqlite_desktop.dart';

AgentTask newTask({int? projectId}) => AgentTask(
  providerId: 1,
  model: 'test',
  protocol: ApiProtocol.openAi,
  goal: 'Research',
  systemPrompt: '',
  projectId: projectId,
);

ModelToolTurn finalTurn(String text) =>
    ModelToolTurn({'role': 'assistant', 'content': text}, text, [], 10, 5);

ModelToolTurn callTurn(
  String id,
  String name,
  Map<String, dynamic> arguments,
) => ModelToolTurn(
  {
    'role': 'assistant',
    'content': null,
    'tool_calls': [
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(arguments)},
      },
    ],
  },
  '',
  [ModelToolCall(id, name, arguments)],
  10,
  5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late AgentStore repository;
  late Database db;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('ai-link-agent-test-');
    databaseFactory = await createDesktopDatabaseFactory(temporary);
    db = await ChatStore.instance.db;
    repository = AgentStore(
      directoryOverride: Directory(p.join(temporary.path, 'artifacts')),
    );
  });
  tearDownAll(() async {
    await db.close();
    await temporary.delete(recursive: true);
  });
  tearDown(() {
    expect(AgentRunner.isBusy, false);
  });

  test('Agent is off when absent, and enable/disable persists without deleting tasks', () async {
    final prefs = AppPreferences.instance;
    expect(prefs.agentEnabled, false);
    final task = newTask();
    await repository.save(task);
    await prefs.setAgentEnabled(true);
    expect(await ChatStore.instance.setting('agent_enabled'), '1');
    await prefs.setAgentEnabled(false);
    expect(await ChatStore.instance.setting('agent_enabled'), '0');
    expect((await repository.tasks()).any((t) => t.id == task.id), true);
    var requested = false;
    final runner = AgentRunner(
      repository: repository,
      turn: (_, _) async {
        requested = true;
        return finalTurn('must not run');
      },
    );
    await runner.run(task);
    expect(requested, false);
    expect(task.status, 'failed');
    runner.dispose();
  });

  test(
    'tool round, final report and evidence survive reload as real files',
    () async {
      final task = newTask();
      var requests = 0;
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (task, tools) async {
          if (requests++ == 0) {
            return callTurn('file1', 'save_artifact', {
              'name': 'comparison.csv',
              'content': 'a,b\n1,2\n',
            });
          }
          expect(task.messages.last['role'], 'tool');
          expect(task.messages.last['tool_call_id'], 'file1');
          return finalTurn('# Findings\nA useful report');
        },
      );
      await runner.run(task);
      expect(task.status, 'completed');
      expect(task.rounds, 2);
      expect(task.calls, 1);
      expect(task.inputTokens, 20);
      expect(task.artifacts.length, 2);
      final restored = (await repository.tasks()).firstWhere(
        (t) => t.id == task.id,
      );
      expect(restored.steps.single['status'], 'completed');
      final report = await repository.artifactFile(
        restored,
        restored.artifacts.last,
      );
      expect(await report.readAsString(), contains('A useful report'));
      await repository.delete(restored);
      expect(await report.exists(), false);
      expect((await repository.tasks()).any((t) => t.id == task.id), false);
      runner.dispose();
    },
  );

  test('CSV preserves quoted cells and neutralizes spreadsheet formulas', () {
    expect(
      safeAgentCsv('name,value\n"a,b","line1\nline2"\n=SUM(A1),"say ""hi"""'),
      '"name","value"\r\n"a,b","line1\nline2"\r\n"\'=SUM(A1)","say ""hi"""',
    );
    expect(() => safeAgentCsv('"unclosed'), throwsFormatException);
    expect(() => safeAgentCsv('"closed"junk'), throwsFormatException);
  });

  test(
    'finished model output recovers file delivery without another model round',
    () async {
      final task = newTask();
      task.finalReady = true;
      task.answer = 'Saved final response';
      task.rounds = 12;
      task.messages.add({'role': 'assistant', 'content': task.answer});
      var requested = false;
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async {
          requested = true;
          return finalTurn('Unexpected');
        },
      );
      await runner.run(task);
      expect(requested, false);
      expect(task.status, 'completed');
      expect(
        await (await repository.artifactFile(
          task,
          task.artifacts.single,
        )).readAsString(),
        contains('Saved final response'),
      );
      runner.dispose();
    },
  );

  test('pending tool resumes without replaying a completed tool or duplicating files', () async {
    final task = newTask();
    final call = callTurn('file1', 'save_artifact', {
      'name': 'notes.md',
      'content': '# Note',
    });
    task.messages.addAll([
      {'role': 'user', 'content': task.goal},
      call.message,
    ]);
    task.rounds = 1;
    task.steps.add({
      'name': 'save_artifact',
      'arguments': call.calls.single.arguments,
      'status': 'running',
    });
    task.pending.add({...call.calls.single.toJson(), 'step': 0});
    // Simulate termination after writing a file but before checkpointing its result.
    await repository.writeArtifact(task, '0', 'notes.md', '# Note');
    await repository.save(task);
    final restored = (await repository.tasks()).firstWhere(
      (t) => t.id == task.id,
    );
    final runner = AgentRunner(
      repository: repository,
      allowed: () async => true,
      turn: (_, _) async => finalTurn('Finished'),
    );
    await runner.run(restored);
    expect(restored.pending, isEmpty);
    expect(restored.artifacts.where((a) => a['name'] == 'notes.md').length, 1);
    expect(
      restored.messages.where((m) => m['tool_call_id'] == 'file1').length,
      1,
    );
    expect(restored.status, 'completed');
    runner.dispose();
  });

  test(
    'pause discards late model calls, and manual resume can finish',
    () async {
      final task = newTask();
      final started = Completer<void>();
      final response = Completer<ModelToolTurn>();
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) {
          started.complete();
          return response.future;
        },
      );
      final run = runner.run(task);
      await started.future;
      runner.pause();
      response.complete(
        callTurn('late', 'save_artifact', {
          'name': 'bad.md',
          'content': 'late',
        }),
      );
      await run;
      expect(task.status, 'paused');
      expect(task.steps, isEmpty);
      expect(task.artifacts, isEmpty);
      runner.dispose();
      final resumed = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async => finalTurn('Resumed'),
      );
      await resumed.run(task);
      expect(task.status, 'completed');
      resumed.dispose();
    },
  );

  test('disabling Agent pauses an active task before another action', () async {
    await AppPreferences.instance.setAgentEnabled(true);
    final task = newTask();
    final started = Completer<void>();
    final response = Completer<ModelToolTurn>();
    final runner = AgentRunner(
      repository: repository,
      turn: (_, _) {
        started.complete();
        return response.future;
      },
    );
    final run = runner.run(task);
    await started.future;
    await AppPreferences.instance.setAgentEnabled(false);
    response.complete(finalTurn('late'));
    await run;
    expect(task.status, 'paused');
    expect(task.artifacts, isEmpty);
    runner.dispose();
  });

  test('model round budget stops loops and preserves progress', () async {
    final task = newTask();
    final runner = AgentRunner(
      repository: repository,
      allowed: () async => true,
      turn: (t, _) async => callTurn('c${t.rounds}', 'unknown', {}),
      execute: (_, _, _) async => {'ok': true},
    );
    await runner.run(task);
    expect(task.rounds, 12);
    expect(task.calls, 12);
    expect(task.status, 'failed');
    expect(task.steps.every((s) => s['status'] == 'completed'), true);
    runner.dispose();
  });

  test(
    'project document access rejects other projects and traversal filenames',
    () async {
      final first = await ChatStore.instance.saveProject(name: 'First');
      final second = await ChatStore.instance.saveProject(name: 'Second');
      final doc = await db.insert('knowledge_documents', {
        'project_id': second,
        'name': 'Secret',
        'content': 'Private data',
        'characters': 12,
        'bytes': 12,
      });
      final task = newTask(projectId: first);
      final runner = AgentRunner(repository: repository);
      expect(
        () => runner.executeTool(
          task,
          ModelToolCall('d', 'read_project_document', {'document_id': doc}),
          0,
        ),
        throwsFormatException,
      );
      expect(
        () => repository.writeArtifact(task, '0', '../outside.md', 'bad'),
        throwsFormatException,
      );
      expect(
        () => runner.executeTool(
          task,
          const ModelToolCall('u', 'shell', {'command': 'pwd'}),
          0,
        ),
        throwsFormatException,
      );
      final result = await runner.executeTool(
        newTask(projectId: second),
        ModelToolCall('d', 'read_project_document', {'document_id': doc}),
        0,
      );
      expect(result['text'], 'Private data');
      runner.dispose();
    },
  );
}
