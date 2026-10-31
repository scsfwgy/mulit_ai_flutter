import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/agent_tools.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

class _Store extends Fake implements ChatStore {
  final settings = <String, String>{};
  @override
  Future<String?> setting(String key) async => settings[key];
}

class _PendingClient extends Fake implements HttpClient {
  final started = Completer<void>();
  final request = Completer<HttpClientRequest>();
  bool closed = false;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  set findProxy(String Function(Uri)? value) {}
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value,
  ) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    started.complete();
    return request.future;
  }

  @override
  void close({bool force = false}) {
    closed = force;
    if (!request.isCompleted) {
      request.completeError(const SocketException('Cancelled'));
    }
  }
}

AgentTask _task({int? projectId}) => AgentTask(
  providerId: 1,
  model: 'test',
  protocol: ApiProtocol.openAi,
  goal: 'Fixture',
  systemPrompt: '',
  projectId: projectId,
);

void main() {
  test(
    'one registry supplies native schemas, availability and translated names',
    () {
      expect(agentToolRegistry.keys, [
        'search_web',
        'read_webpage',
        'search_project',
        'read_project_document',
        'save_artifact',
      ]);
      expect(() => agentToolRegistry.clear(), throwsUnsupportedError);
      expect(agentTools(project: false, search: false).map((t) => t['name']), [
        'read_webpage',
        'save_artifact',
      ]);
      expect(agentTools(project: true, search: false).map((t) => t['name']), [
        'read_webpage',
        'search_project',
        'read_project_document',
        'save_artifact',
      ]);
      expect(agentTools(project: false, search: true).map((t) => t['name']), [
        'search_web',
        'read_webpage',
        'save_artifact',
      ]);
      final tools = agentTools(project: true, search: true);
      for (final tool in tools) {
        final definition = agentToolRegistry[tool['name']]!;
        final parameters = tool['parameters'] as Map;
        expect(parameters['additionalProperties'], false);
        expect(
          (parameters['required'] as List).every(
            (key) => (parameters['properties'] as Map).containsKey(key),
          ),
          true,
        );
        for (final language in I18n.languages) {
          expect(I18n.lookupIn(language, definition.labelKey), isNotNull);
        }
        expect(agentToolLabel(tool['name'] as String), T(definition.labelKey));
      }
      for (final protocol in ApiProtocol.values) {
        final body = modelToolBody(protocol, 'test', '', [], tools);
        final wire = (body['tools'] as List).cast<Map>();
        expect(wire.length, tools.length);
        for (var i = 0; i < tools.length; i++) {
          final definition = protocol == ApiProtocol.openAi
              ? wire[i]['function'] as Map
              : wire[i];
          expect(definition['name'], tools[i]['name']);
          expect(
            definition[protocol == ApiProtocol.openAi
                ? 'parameters'
                : 'input_schema'],
            tools[i]['parameters'],
          );
        }
      }
    },
  );

  test('dispatch rejects unknown, missing, extra and mistyped arguments before side effects', () async {
    final executor = AgentToolExecutor(
      repository: AgentStore(store: _Store()),
      check: () {},
    );
    final task = _task(projectId: 1);
    for (final call in [
      const ModelToolCall('u', 'shell', {'command': 'pwd'}),
      const ModelToolCall('m', 'save_artifact', {'name': 'result.md'}),
      const ModelToolCall('e', 'save_artifact', {
        'name': 'result.md',
        'content': 'text',
        'extra': 'ignored?',
      }),
      const ModelToolCall('t', 'read_project_document', {'document_id': '1'}),
      const ModelToolCall('o', 'read_project_document', {
        'document_id': 1,
        'offset': -1,
      }),
      const ModelToolCall('s', 'save_artifact', {
        'name': '',
        'content': 'text',
      }),
      const ModelToolCall('i', 'save_artifact', {
        'name': 'result.md',
        'content': 'text',
      }, argumentError: true),
    ]) {
      await expectLater(executor.execute(task, call, 0), throwsFormatException);
    }
    expect(task.artifacts, isEmpty);
    expect(task.sources, isEmpty);
    executor.cancel();
  });

  test('project and search restrictions are enforced at execution, not just hidden from the model', () async {
    final store = _Store();
    final executor = AgentToolExecutor(
      repository: AgentStore(store: store),
      check: () {},
    );
    for (final call in [
      const ModelToolCall('s', 'search_project', {'query': 'private'}),
      const ModelToolCall('r', 'read_project_document', {'document_id': 1}),
      const ModelToolCall('w', 'search_web', {'query': 'public'}),
    ]) {
      await expectLater(
        executor.execute(_task(), call, 0),
        throwsFormatException,
      );
    }
    executor.cancel();
  });

  test('registered file handler preserves artifact paths and serialized task records', () async {
    final temporary = await Directory.systemTemp.createTemp('agent-tools-');
    final repository = AgentStore(
      store: _Store(),
      directoryOverride: temporary,
    );
    final executor = AgentToolExecutor(repository: repository, check: () {});
    try {
      final task = _task();
      final result = await executor.execute(
        task,
        const ModelToolCall('file', 'save_artifact', {
          'name': 'result.md',
          'content': '# Saved result',
        }),
        3,
      );
      expect(result['saved'], 'result.md');
      final restored = AgentTask.fromJson(task.toJson());
      expect(restored.artifacts.single['file'], '3.md');
      expect(
        await (await repository.artifactFile(
          restored,
          restored.artifacts.single,
        )).readAsString(),
        '# Saved result',
      );
    } finally {
      executor.cancel();
      await temporary.delete(recursive: true);
    }
  });

  test('a paused run cannot enter a registered handler', () async {
    final task = _task();
    final executor = AgentToolExecutor(
      repository: AgentStore(store: _Store()),
      check: () => throw StateError('paused'),
    );
    await expectLater(
      executor.execute(
        task,
        const ModelToolCall('file', 'save_artifact', {
          'name': 'result.md',
          'content': 'text',
        }),
        0,
      ),
      throwsStateError,
    );
    expect(task.artifacts, isEmpty);
    executor.cancel();
  });

  test(
    'cancel still closes the web reader while a request is pending',
    () async {
      final client = _PendingClient();
      await HttpOverrides.runZoned(() async {
        final task = _task();
        final executor = AgentToolExecutor(
          repository: AgentStore(store: _Store()),
          check: () {},
        );
        final pending = executor.execute(
          task,
          const ModelToolCall('web', 'read_webpage', {
            'url': 'https://example.com',
          }),
          0,
        );
        await client.started.future;
        executor.cancel();
        await expectLater(pending, throwsA(isA<SocketException>()));
        expect(client.closed, true);
        expect(task.sources, isEmpty);
      }, createHttpClient: (_) => client);
    },
  );
}
