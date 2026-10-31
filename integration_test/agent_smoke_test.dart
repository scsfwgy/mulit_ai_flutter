import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/main.dart' as app;
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_feature_hints.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';

/// A local protocol fixture exercises actual model HTTP, SQLite, files and UI.
/// It restores settings and deletes only the provider/project/task it created.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Agent is opt-in and delivers a project report with a real file', (
    tester,
  ) async {
    final store = ChatStore.instance;
    binding.testTextInput.register();
    addTearDown(binding.testTextInput.unregister);
    final repository = AgentStore();
    final saved = <String, String?>{};
    for (final key in [
      'agent_enabled',
      'agent_context_window_tokens',
      'app_language',
      'global_prompt',
      'last_chat_selection',
    ]) {
      saved[key] = await store.setting(key);
    }
    final taskIds = (await repository.tasks()).map((t) => t.id).toSet();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      if (body['stream'] == true) {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"Agent QA"}}]}\n\ndata: [DONE]\n\n',
        );
        await request.response.close();
        return;
      }
      requests++;
      request.response.headers.contentType = ContentType.json;
      if (requests == 1) {
        expectSync(body['max_tokens'], 16384);
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'length',
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'reasoning_content': 'Unfinished',
                },
              },
            ],
            'usage': {'prompt_tokens': 10, 'completion_tokens': 16384},
          }),
        );
      } else if (requests == 2) {
        expectSync(body['max_tokens'], 32768);
        expectSync(body['tools'], isNotEmpty);
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'project-lookup',
                      'type': 'function',
                      'function': {
                        'name': 'search_project',
                        'arguments': '{"query":"Agent research"}',
                      },
                    },
                  ],
                },
              },
            ],
            'usage': {'prompt_tokens': 20, 'completion_tokens': 5},
          }),
        );
      } else if (requests == 3) {
        expectSync(body['messages'].last['role'], 'tool');
        expectSync(
          body['messages'].last['content'],
          contains('Project fixture'),
        );
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'save-report',
                      'type': 'function',
                      'function': {
                        'name': 'save_artifact',
                        'arguments': jsonEncode({
                          'name': 'report.md',
                          'content': '# Agent 研究报告\n\n项目资料已读取，报告文件已准备。',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
            'usage': {'prompt_tokens': 30, 'completion_tokens': 10},
          }),
        );
      } else if (requests == 4) {
        request.response.statusCode = 400;
        request.response.write(
          '{"error":{"code":"invalid_request","message":"Fixture failure after saved tools"}}',
        );
      } else {
        expectSync(body['messages'].last['tool_call_id'], 'save-report');
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'role': 'assistant',
                  'content': '# Agent 研究报告\n\n项目资料已读取，报告文件已准备。',
                },
              },
            ],
            'usage': {'prompt_tokens': 40, 'completion_tokens': 10},
          }),
        );
      }
      await request.response.close();
    });
    int? providerId;
    int? projectId;
    int? topicId;
    try {
      await store.saveSetting('agent_enabled', '0');
      await store.saveSetting('app_language', 'zh');
      await store.saveSetting('global_prompt', '');
      providerId = await store.saveProvider(
        ProviderConfig(
          id: 0,
          name: 'Agent local fixture',
          protocol: ApiProtocol.openAi,
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'local-agent',
        ),
        apiKey: 'temporary-local-key',
      );
      await store.saveLastChatSelection(
        ChatSelection(providerId, 'local-agent'),
      );
      final provider = (await store.providers()).firstWhere(
        (p) => p.id == providerId,
      );
      topicId = await store.createTopicWithMessage(
        provider,
        'local-agent',
        'Check a long comparison table',
      );
      final fixtureTitle = 'Agent QA conversation $providerId';
      await store.updateTopic(topicId, title: fixtureTitle);
      await store.addMessage(
        topicId,
        'assistant',
        '| Plan | Notes |\n|---|---|\n| Local | ${'Long comparison notes. ' * 20} |\n| Remote | Requires a connection |',
      );
      projectId = await store.saveProject(name: 'Agent QA project');
      await store.addKnowledge(
        projectId,
        'Project fixture',
        'Agent research uses local project documents.',
      );
      await store.moveTopic(topicId, projectId);
      await app.main();
      for (
        var i = 0;
        i < 100 &&
            find.byIcon(CupertinoIcons.line_horizontal_3).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agent-entry')), findsNothing);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('agent-default-off-welcome');
      await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('agent-topic-list');
      await tester.tap(find.text(fixtureTitle));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('agent-existing-chat-table');
      Navigator.of(tester.element(find.byType(Scaffold).first))
          .push(appPageRouteForTest(const ProviderScreen()));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('agent-provider-list');
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first))
          .push(appPageRouteForTest(ProviderEditor(config: provider)));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('agent-provider-editor');
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context)
          .push(appPageRouteForTest(const MessageSettingsScreen()));
      await tester.pumpAndSettle();
      final agentRow = find.byKey(const Key('message-agent-settings'));
      await tester.ensureVisible(agentRow);
      await binding.takeScreenshot('agent-message-settings-off');
      await tester.tap(agentRow);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoSwitch>(find.byKey(const Key('agent-enable')))
            .value,
        false,
      );
      await binding.takeScreenshot('agent-settings-off');
      await tester.tap(find.byKey(const Key('agent-enable')));
      await tester.pumpAndSettle();
      expect(await store.setting('agent_enabled'), '1');
      await binding.takeScreenshot('agent-settings-on');
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      expect(find.text(T('i18n.agent_on')), findsOneWidget);
      await binding.takeScreenshot('agent-message-settings-on');
      await tester.tap(find.byKey(const Key('message-agent-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-context-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatContextScreen), findsOneWidget);
      await tester.ensureVisible(find.text('1M Token'));
      await tester.tap(find.text('1M Token'));
      await tester.pumpAndSettle();
      expect(await store.setting('agent_context_window_tokens'), '1048576');
      await binding.takeScreenshot('agent-context-settings');
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byType(ChatComposer),
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(input, '结合项目资料生成 Agent 研究报告并保存 report.md');
      await tester.pump();
      expect(find.byType(ChatFeatureHints), findsOneWidget);
      expect(find.byKey(const Key('agent-entry')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('chat-feature-hints'))).height,
        lessThan(32),
      );
      await binding.takeScreenshot('agent-chat-task-draft');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      binding.testTextInput.unregister();
      await tester.tap(input);
      for (var i = 0; i < 50 && tester.view.viewInsets.bottom == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      final keyboardTop =
          (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
          tester.view.devicePixelRatio;
      expect(
        tester.getRect(find.byType(ChatComposer)).bottom,
        lessThanOrEqualTo(keyboardTop + 1),
      );
      await binding.takeScreenshot('agent-chat-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      binding.testTextInput.register();
      await tester.tap(find.text(T('i18n.send')));
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final tasks = (await repository.tasks()).where(
          (t) => !taskIds.contains(t.id),
        );
        if (tasks.isNotEmpty &&
            tasks.first.status == 'paused' &&
            !AgentRunner.isBusy) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final paused = (await repository.tasks()).firstWhere(
        (t) => !taskIds.contains(t.id),
      );
      expect(paused.status, 'paused');
      expect(requests, 4);
      expect(paused.requests.first['finish_reason'], 'length');
      expect(paused.requests.last['http_status'], 400);
      expect(paused.artifacts.length, 1);
      await binding.takeScreenshot('agent-paused-with-diagnostics');
      await tester.enterText(input, '继续');
      await tester.pump();
      await tester.tap(find.text(T('i18n.send')));
      for (var i = 0; i < 160; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final tasks = (await repository.tasks()).where(
          (t) => !taskIds.contains(t.id),
        );
        if (tasks.isNotEmpty &&
            tasks.first.status == 'completed' &&
            !AgentRunner.isBusy) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final task = (await repository.tasks()).firstWhere(
        (t) => !taskIds.contains(t.id),
      );
      expect(task.id, paused.id);
      expect(task.status, 'completed');
      expect(task.calls, 2);
      expect(requests, 5);
      expect(
        (await repository.tasks()).where((t) => !taskIds.contains(t.id)).length,
        1,
      );
      expect(task.topicId, topicId);
      final history = await store.messages(topicId);
      expect(history.length, 4);
      expect(history.last.id, task.answerMessageId);
      expect(history.last.content, contains('项目资料已读取'));
      expect(task.sources, isNotEmpty);
      expect(
        await (await repository.artifactFile(
          task,
          task.artifacts.single,
        )).exists(),
        true,
      );
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('agent-completed-task');
      await tester.tap(find.text('report.md'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('agent-report-preview');
      expect(find.textContaining('项目资料已读取'), findsWidgets);
    } finally {
      AgentRunner.active?.pause();
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 40 && AgentRunner.isBusy; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (final task in await repository.tasks()) {
        if (!taskIds.contains(task.id)) await repository.delete(task);
      }
      if (projectId != null) await store.deleteProject(projectId);
      if (topicId != null) await store.deleteTopic(topicId);
      if (providerId != null) await store.deleteProvider(providerId);
      for (final entry in saved.entries) {
        if (entry.value == null) {
          await store.deleteSetting(entry.key);
        } else {
          await store.saveSetting(entry.key, entry.value!);
        }
      }
      await AppPreferences.instance.load();
      await server.close(force: true);
    }
  });
}

Route<void> appPageRouteForTest(Widget child) =>
    CupertinoPageRoute(builder: (_) => child);
