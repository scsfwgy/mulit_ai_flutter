import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_tools.dart';
import 'package:mulit_ai_flutter/agent/agent_context.dart';
import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temporary.path,
        );
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

  test(
    'unknown protocols do not hide valid tasks or unrelated chats',
    () async {
      final task = newTask();
      await repository.save(task);
      final key = 'agent_task:damaged';
      await repository.store.saveSetting(
        key,
        jsonEncode(task.toJson()..['protocol'] = 'unknown'),
      );
      try {
        expect((await repository.tasks()).any((t) => t.id == task.id), true);
        expect(await repository.forTopic(-1), isEmpty);
        expect(await repository.store.setting(key), isNotNull);
      } finally {
        await repository.store.deleteSetting(key);
      }
    },
  );

  for (final protocol in ApiProtocol.values) {
    test(
      '${protocol.name} pairs skipped calls before a budget summary',
      () async {
        final task = AgentTask(
          providerId: 1,
          model: 'test',
          protocol: protocol,
          goal: 'Research',
          systemPrompt: '',
        );
        final calls = [
          for (var i = 0; i < 26; i++)
            ModelToolCall('c$i', 'read_webpage', {
              'url': 'https://example.com/$i',
            }),
        ];
        var requests = 0;
        final runner = AgentRunner(
          repository: repository,
          allowed: () async => true,
          execute: (_, _, _) async => {'text': 'Evidence'},
          turn: (t, _) async {
            if (requests++ > 0) {
              expect(t.finishNotice, 'budget');
              expect(t.pending, isEmpty);
              final results = protocol == ApiProtocol.openAi
                  ? t.messages.where((m) => m['role'] == 'tool').toList()
                  : (t.messages.last['content'] as List).cast<Map>();
              expect(results.length, 26);
              expect(
                results.map(
                  (r) =>
                      r[protocol == ApiProtocol.openAi
                          ? 'tool_call_id'
                          : 'tool_use_id'],
                ),
                calls.map((c) => c.id),
              );
              expect(
                jsonDecode(results.last['content'] as String)['code'],
                'run_budget',
              );
              return finalTurn('Partial answer');
            }
            return ModelToolTurn(
              {
                'role': 'assistant',
                if (protocol == ApiProtocol.openAi) ...{
                  'content': null,
                  'tool_calls': [
                    for (final c in calls)
                      {
                        'id': c.id,
                        'type': 'function',
                        'function': {
                          'name': c.name,
                          'arguments': jsonEncode(c.arguments),
                        },
                      },
                  ],
                } else
                  'content': [
                    for (final c in calls)
                      {
                        'type': 'tool_use',
                        'id': c.id,
                        'name': c.name,
                        'input': c.arguments,
                      },
                  ],
              },
              '',
              calls,
              10,
              5,
            );
          },
        );
        await runner.run(task);
        runner.dispose();
        expect(task.status, 'completed');
        expect(task.calls, 24);
        expect(task.steps.where((s) => s['status'] == 'skipped').length, 2);
        expect(task.requests.last['tools_enabled'], false);
        expect(requests, 2);
      },
    );
  }

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

  test('debug logs record the run without task text or secrets', () async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    addTearDown(() => debugPrint = previous);
    final task = newTask();
    final runner = AgentRunner(
      repository: repository,
      allowed: () async => true,
      turn: (_, tools) async {
        expect(
          tools.map((tool) => tool['name']),
          isNot(contains('search_web')),
        );
        return finalTurn('private answer text');
      },
    );
    await runner.run(task);
    runner.dispose();
    final trace = lines
        .where((line) => line.startsWith('[AI Link Agent]'))
        .join('\n');
    expect(trace, contains('"event":"start"'));
    expect(trace, contains('"event":"turn"'));
    expect(trace, contains('"status":"completed"'));
    expect(trace, contains('"event":"end"'));
    expect(trace, contains('"stop":"completed"'));
    expect(trace, isNot(contains('Research')));
    expect(trace, isNot(contains('private answer text')));
    expect(trace, isNot(contains('Bearer')));
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

  test(
    'a competing task reports busy while the active request winds down',
    () async {
      final response = Completer<ModelToolTurn>();
      final started = Completer<void>();
      final first = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) {
          started.complete();
          return response.future;
        },
      );
      final second = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async => finalTurn('Unexpected'),
      );
      final run = first.run(newTask());
      await started.future;
      await expectLater(() => second.run(newTask()), throwsException);
      first.pause();
      response.complete(finalTurn('Late'));
      await run;
      first.dispose();
      second.dispose();
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

  test(
    'last budgeted request returns an interim answer with tools disabled',
    () async {
      final task = newTask();
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (t, _) async => t.finishNotice != null
            ? finalTurn('Established facts and remaining questions')
            : callTurn('c${t.rounds}', 'unknown', {'query': '${t.rounds}'}),
        execute: (_, _, _) async => {'ok': true},
      );
      await runner.run(task);
      expect(task.rounds, 12);
      expect(task.calls, 11);
      expect(task.status, 'completed');
      expect(task.finishNotice, 'budget');
      expect(task.requests.last['tools_enabled'], false);
      expect(task.answer, contains('remaining questions'));
      runner.dispose();
    },
  );

  test(
    'repeated identical tools stop early and summarize existing evidence',
    () async {
      final task = newTask();
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (t, _) async => t.finishNotice != null
            ? finalTurn('Evidence is insufficient')
            : callTurn('c${t.rounds}', 'unknown', {'query': 'same'}),
        execute: (_, _, _) async => {'ok': true},
      );
      await runner.run(task);
      expect(task.calls, 3);
      expect(task.rounds, 4);
      expect(task.status, 'completed');
      expect(task.finishNotice, 'loop');
      runner.dispose();
    },
  );

  test('old lifetime-budget failures resume with a fresh run budget', () async {
    final task = newTask()
      ..rounds = 12
      ..calls = 24
      ..status = 'failed';
    expect(task.canResume, true);
    final runner = AgentRunner(
      repository: repository,
      allowed: () async => true,
      turn: (_, _) async => finalTurn('Recovered'),
    );
    await runner.run(task);
    expect(task.status, 'completed');
    expect(task.rounds, 13);
    runner.dispose();
  });

  test(
    'truncated output grows its own reserve and retries without executing it',
    () async {
      final task = newTask();
      var count = 0;
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async {
          if (count++ == 0) {
            throw const ModelTurnException(
              'output_limit',
              finishReason: 'length',
              inputTokens: 10,
              outputTokens: 8192,
            );
          }
          return finalTurn('Complete');
        },
      );
      await runner.run(task);
      expect(task.status, 'completed');
      expect(task.calls, 0);
      expect(task.outputTokenLimit, 16384);
      expect(task.requests.first['finish_reason'], 'length');
      expect(task.requests.first['status'], 'retrying');
      expect(task.inputTokens, 20);
      expect(task.outputTokens, 8197);
      expect(task.usageComplete, true);
      runner.dispose();
    },
  );

  test(
    'invalid tool arguments are returned for correction without calling a tool',
    () async {
      final task = newTask();
      var attempts = 0;
      var executions = 0;
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (t, _) async {
          if (attempts++ == 0) {
            return ModelToolTurn(
              {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'bad',
                    'type': 'function',
                    'function': {'name': 'search_web', 'arguments': '{'},
                  },
                ],
              },
              '',
              [
                const ModelToolCall(
                  'bad',
                  'search_web',
                  {},
                  argumentError: true,
                ),
              ],
              10,
              5,
            );
          }
          if (attempts == 2) {
            expect(t.messages.last['content'], contains('invalid_arguments'));
            return callTurn('fixed', 'search_web', {'query': 'fixed'});
          }
          return finalTurn('Done');
        },
        execute: (_, _, _) async {
          executions++;
          return {'text': 'Evidence'};
        },
      );
      await runner.run(task);
      expect(task.status, 'completed');
      expect(executions, 1);
      expect(task.steps.first['status'], 'failed');
      expect(task.messages.where((m) => m['tool_call_id'] == 'bad').length, 1);
      runner.dispose();
    },
  );

  test(
    'rate limits retry, while malformed model output pauses with diagnostics',
    () async {
      final task = newTask();
      var count = 0;
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async {
          if (count++ == 0) {
            throw const ApiException('Rate limited', statusCode: 429);
          }
          throw const ModelTurnException(
            'invalid_response',
            finishReason: 'unexpected',
          );
        },
      );
      await runner.run(task);
      expect(task.status, 'paused');
      expect(task.requests.first['http_status'], 429);
      expect(task.requests.last['finish_reason'], 'unexpected');
      expect(task.canResume, true);
      final restored = (await repository.tasks()).firstWhere(
        (t) => t.id == task.id,
      );
      expect(restored.requests, task.requests);
      expect(restored.errorCode, 'invalid_response');
      runner.dispose();
    },
  );

  test(
    'Agent budget persists independently and can unblock a paused request',
    () async {
      final prefs = AppPreferences.instance;
      await prefs.setContextWindowTokens(8192);
      await prefs.setAgentContextWindowTokens(8192);
      final task = newTask();
      task.messages.add({'role': 'user', 'content': 'large request ' * 1500});
      var requested = 0;
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async {
          requested++;
          return finalTurn('Done');
        },
      );
      await runner.run(task);
      expect(task.status, 'paused');
      expect(task.contextBlocked, true);
      expect(task.rounds, 0);
      expect(requested, 0);
      await prefs.setAgentContextWindowTokens(32768);
      expect(
        await ChatStore.instance.setting(AgentContext.settingKey),
        '32768',
      );
      expect(await ChatStore.instance.setting(ChatContext.settingKey), '8192');
      await runner.run(task);
      expect(task.status, 'completed');
      expect(requested, 1);
      expect(prefs.contextWindowTokens, 8192);
      runner.dispose();
    },
  );

  test(
    'linked completion publishes once and stale conversations cannot resume',
    () async {
      final store = ChatStore.instance;
      final provider = ProviderConfig(
        id: 1,
        name: 'Snapshot',
        protocol: ApiProtocol.openAi,
        baseUrl: 'https://example.com',
        model: 'test',
      );
      await db.insert('providers', {
        'id': 1,
        'name': 'Snapshot',
        'protocol': ApiProtocol.openAi.value,
        'base_url': 'https://example.com',
        'model': 'test',
      });
      final topicId = await store.createTopicWithMessage(
        provider,
        'test',
        'Research',
      );
      final userId = (await store.messages(topicId)).single.id;
      final task = AgentTask(
        providerId: 1,
        providerName: 'Snapshot',
        model: 'test',
        protocol: ApiProtocol.openAi,
        goal: 'Research',
        systemPrompt: '',
        topicId: topicId,
        userMessageId: userId,
      );
      final runner = AgentRunner(
        repository: repository,
        allowed: () async => true,
        turn: (_, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return finalTurn('Completed in chat');
        },
      );
      task.sources.add({
        'documentId': 123,
        'label': 'D123@8000',
        'title': 'Project evidence',
        'excerpt': 'Exact supplied snapshot',
      });
      final updates = <String>[];
      final subscription = AgentRunner.updates.listen((changed) {
        if (changed.id == task.id) {
          updates.add('${changed.status}:${AgentRunner.isBusy}');
        }
      });
      await runner.run(task);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(updates, contains('running:true'));
      expect(updates.last, 'completed:false');
      expect(task.status, 'completed');
      expect(task.artifacts, isEmpty);
      final restored = (await repository.forTopic(topicId))[userId]!;
      await repository.save(restored);
      await repository.save(task);
      final messages = await store.messages(topicId);
      expect(messages.map((m) => m.role), ['user', 'assistant']);
      expect(messages.last.content, 'Completed in chat');
      expect(messages.last.providerName, 'Snapshot');
      expect(messages.last.totalMs, greaterThanOrEqualTo(10));
      expect(messages.last.firstTokenMs, isNull);
      expect(messages.last.knowledgeSources.single.label, 'D123@8000');
      expect(
        messages.last.knowledgeSources.single.text,
        'Exact supplied snapshot',
      );
      expect(restored.totalMs, messages.last.totalMs);
      expect(restored.answerMessageId, messages.last.id);
      runner.dispose();
      final files = AgentStore();
      await files.writeArtifact(task, '0', 'notes.md', 'Content');
      await files.save(task);
      final file = await files.artifactFile(task, task.artifacts.single);
      await store.deleteTopic(topicId);
      expect(await file.exists(), false);
      expect((await repository.forTopic(topicId)), isEmpty);
      expect(() => repository.save(task), throwsStateError);

      final staleTopic = await store.createTopicWithMessage(
        provider,
        'test',
        'First',
      );
      final firstId = (await store.messages(staleTopic)).single.id;
      final stale = AgentTask(
        providerId: 1,
        model: 'test',
        protocol: ApiProtocol.openAi,
        goal: 'First',
        systemPrompt: '',
        topicId: staleTopic,
        userMessageId: firstId,
      );
      await repository.save(stale);
      await store.addMessage(staleTopic, 'user', 'New message');
      stale.status = 'completed';
      stale.answer = 'Must not publish';
      expect(() => repository.save(stale), throwsStateError);
      expect(stale.answerMessageId, isNull);
      expect(
        (await store.messages(staleTopic)).where((m) => m.role == 'assistant'),
        isEmpty,
      );
      await store.deleteTopic(staleTopic);
    },
  );

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
      final executor = AgentToolExecutor(repository: repository, check: () {});
      expect(
        () => executor.execute(
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
        () => executor.execute(
          task,
          const ModelToolCall('u', 'shell', {'command': 'pwd'}),
          0,
        ),
        throwsFormatException,
      );
      final result = await executor.execute(
        newTask(projectId: second),
        ModelToolCall('d', 'read_project_document', {'document_id': doc}),
        0,
      );
      expect(result['text'], 'Private data');
      executor.cancel();
    },
  );
}
