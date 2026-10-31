import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_screen.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/agent/chat_agent_card.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

import 'sqflite_stub.dart';

AgentTask task() => AgentTask(
  providerId: 1,
  model: 'test',
  protocol: ApiProtocol.openAi,
  goal: 'Question',
  systemPrompt: '',
  topicId: 7,
  userMessageId: 11,
);

void main() {
  setUpAll(useSqflitePluginFactory);

  for (final fromMessageSettings in [false, true]) {
    testWidgets(
      'task recovery returns its chat through nested settings ($fromMessageSettings)',
      (tester) async {
        final t = task()..errorCode = 'model';
        installEmptyDatabaseStub(
          settings: {
            'agent_task:*': jsonEncode(t.toJson()),
            'agent_enabled': '1',
          },
        );
        AppPreferences.instance.agentEnabled = true;
        Object? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: CupertinoButton(
                  onPressed: () async {
                    result = await Navigator.push<Object>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => fromMessageSettings
                            ? const MessageSettingsScreen()
                            : const SettingsScreen(),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(IosRow, T('i18n.agent_title')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(IosRow, T('i18n.agent_history')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.goal));
        await tester.pumpAndSettle();
        final action = find.byKey(const Key('agent-recovery-action'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(result, isA<AgentChatRequest>());
        final target = result as AgentChatRequest;
        expect(target.task.id, t.id);
        expect(target.changeModel, true);
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('activity follows the executing call and then the model, not the last queued tool', () {
    final t = task()..status = 'running';
    t.steps.addAll([
      {'name': 'read_webpage', 'status': 'running'},
      {'name': 'save_artifact', 'status': 'pending'},
    ]);
    t.pending.addAll([
      {'name': 'read_webpage', 'step': 0},
      {'name': 'save_artifact', 'step': 1},
    ]);
    expect(agentActivity(t), T('i18n.agent_tool_read'));
    t.pending.removeAt(0);
    t.steps.first['status'] = 'completed';
    expect(agentActivity(t), T('i18n.agent_preparing'));
    t.steps.last['status'] = 'running';
    expect(agentActivity(t), T('i18n.agent_tool_save'));
    t.pending.clear();
    t.steps.last['status'] = 'completed';
    t.requests.add({'status': 'running', 'tools_enabled': true});
    expect(agentActivity(t), T('i18n.agent_waiting_model'));
    t.requests.last['tools_enabled'] = false;
    expect(agentActivity(t), T('i18n.agent_organizing_answer'));
    t.requests.last['status'] = 'retrying';
    expect(agentActivity(t), T('i18n.agent_retry_wait'));
    t.finalReady = true;
    expect(agentActivity(t), T('i18n.agent_saving_result'));
  });

  test(
    'recovery is based on saved error codes and supports older request records',
    () {
      final expected = {
        'network': AgentRecoveryAction.resume,
        'auth': AgentRecoveryAction.service,
        'model': AgentRecoveryAction.model,
        'invalid_response': AgentRecoveryAction.service,
        'i18n.this_service_has_no_api': AgentRecoveryAction.service,
        'i18n.agent_chat_changed': AgentRecoveryAction.chat,
        'i18n.agent_provider_changed': AgentRecoveryAction.model,
        'i18n.agent_access': AgentRecoveryAction.purchase,
      };
      for (final entry in expected.entries) {
        final t = task()
          ..errorCode = entry.key
          ..error = 'Failure';
        expect(
          agentRecoveryAction(AgentTask.fromJson(t.toJson())),
          entry.value,
        );
      }
      final legacy = task()..error = 'Failure';
      legacy.requests.add({'code': 'auth', 'http_status': 401});
      expect(agentRecoveryAction(legacy), AgentRecoveryAction.service);
      legacy.requests.last.addAll({'code': 'other', 'http_status': 429});
      expect(agentRecoveryAction(legacy), AgentRecoveryAction.resume);
      legacy.contextBlocked = true;
      expect(agentRecoveryAction(legacy), AgentRecoveryAction.context);
    },
  );

  testWidgets(
    'completed card is compact and details retain diagnostics without a resume button',
    (tester) async {
      installEmptyDatabaseStub();
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final t = task()
        ..status = 'completed'
        ..rounds = 4
        ..calls = 6
        ..contextTokens = 8000
        ..contextWindowTokens = 32768
        ..contextCompacted = true;
      t.answer = 'Saved result';
      t.artifacts.add({'name': 'result.md', 'file': '0.md'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatAgentCard(
              task: t,
              running: false,
              onDetails: () {},
              onResume: () {},
            ),
          ),
        ),
      );
      expect(find.text(F('i18n.agent_progress', [4, 6])), findsNothing);
      expect(find.textContaining('8000'), findsNothing);
      expect(find.text(T('i18n.agent_context_compacted')), findsNothing);
      expect(find.text(T('i18n.agent_resume')), findsNothing);
      expect(find.text('result.md'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: AgentTaskScreen(task: t)));
      await tester.pumpAndSettle();
      expect(find.text(F('i18n.agent_progress', [4, 6])), findsOneWidget);
      expect(
        find.text(F('i18n.agent_context_usage', [8000, 32768])),
        findsOneWidget,
      );
      expect(find.text(T('i18n.agent_resume')), findsNothing);
      expect(find.text(T('i18n.agent_context_compacted')), findsOneWidget);
      expect(find.text('Saved result'), findsOneWidget);
      expect(find.text('result.md'), findsOneWidget);
    },
  );

  testWidgets('network recovery offers one explicit resume action', (
    tester,
  ) async {
    AppPreferences.instance.agentEnabled = true;
    final t = task()
      ..errorCode = 'network'
      ..error = 'Connection failed';
    var resumed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAgentCard(
            task: t,
            running: false,
            onDetails: () {},
            onResume: () => resumed++,
          ),
        ),
      ),
    );
    expect(find.text(T('i18n.agent_resume')), findsOneWidget);
    expect(find.text(T('i18n.check_service_settings')), findsNothing);
    await tester.tap(find.byKey(const Key('agent-recovery-action')));
    await tester.pump();
    expect(resumed, 1);
  });

  testWidgets(
    'auth recovery opens the original provider and does not retry automatically',
    (tester) async {
      installEmptyDatabaseStub(
        providers: [
          {
            'id': 1,
            'name': 'Original service',
            'protocol': ApiProtocol.openAi.value,
            'base_url': 'https://example.com/v1',
            'model': 'test',
          },
        ],
      );
      AppPreferences.instance.agentEnabled = true;
      final t = task()
        ..errorCode = 'auth'
        ..error = 'Key rejected';
      var resumed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentTaskActions(task: t, onResume: () => resumed++),
          ),
        ),
      );
      expect(find.text(T('i18n.agent_resume')), findsNothing);
      await tester.tap(find.text(T('i18n.check_service_settings')));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderEditor), findsOneWidget);
      expect(find.text('Original service'), findsOneWidget);
      expect(resumed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adjusting context offers resume only after returning and does not execute automatically',
    (tester) async {
      installEmptyDatabaseStub();
      AppPreferences.instance.agentEnabled = true;
      AppPreferences.instance.agentContextWindowTokens = 32768;
      final t = task()..contextBlocked = true;
      var resumed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentTaskActions(task: t, onResume: () => resumed++),
          ),
        ),
      );
      expect(find.text(T('i18n.agent_resume')), findsNothing);
      await tester.tap(find.text(T('i18n.agent_adjust_context')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatContextScreen), findsOneWidget);
      await tester.tap(find.text('64K Token'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await tester.pumpAndSettle();
      expect(resumed, 0);
      expect(find.text(T('i18n.agent_adjust_context')), findsNothing);
      await tester.tap(find.text(T('i18n.agent_resume')));
      await tester.pump();
      expect(resumed, 1);
    },
  );

  testWidgets(
    'model recovery returns a chat target, preserving the original task',
    (tester) async {
      AppPreferences.instance.agentEnabled = true;
      final t = task()..errorCode = 'model';
      AgentChatRequest? target;
      var resumed = 0;
      Widget actions({bool changed = false}) => MaterialApp(
        home: Scaffold(
          body: AgentTaskActions(
            task: t,
            onResume: () => resumed++,
            onOpenChat: (value) => target = value,
            retryWithCurrentModel: changed,
          ),
        ),
      );
      await tester.pumpWidget(actions());
      await tester.tap(find.text(T('i18n.switch_model')));
      await tester.pump();
      expect(target!.task, same(t));
      expect(target!.changeModel, true);
      expect(resumed, 0);
      await tester.pumpWidget(actions(changed: true));
      expect(find.text(T('i18n.agent_model_changed_retry')), findsOneWidget);
      await tester.tap(find.text(T('i18n.retry_response')));
      await tester.pump();
      expect(resumed, 1);
      expect(t.model, 'test');
    },
  );

  testWidgets(
    'compact message info hides field controls and restores their saved choices',
    (tester) async {
      installEmptyDatabaseStub();
      final prefs = AppPreferences.instance;
      prefs.simpleMessageInfo = false;
      await prefs.setChatInfoVisible(ChatInfoField.tokens, false);
      await tester.pumpWidget(const MaterialApp(home: MessageSettingsScreen()));
      await tester.pumpAndSettle();
      final toggle = find.descendant(
        of: find.widgetWithText(IosRow, T('i18n.simple_mode')),
        matching: find.byType(CupertinoSwitch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      for (final field in ChatInfoField.values) {
        expect(find.widgetWithText(IosRow, T(field.label)), findsNothing);
      }
      expect(find.text(T('i18n.chat_features_scope')), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final tokens = find.descendant(
        of: find.widgetWithText(IosRow, T(ChatInfoField.tokens.label)),
        matching: find.byType(CupertinoSwitch),
      );
      await tester.scrollUntilVisible(tokens, 200);
      expect(tester.widget<CupertinoSwitch>(tokens).value, false);
      await prefs.setChatInfoVisible(ChatInfoField.tokens, true);
      expect(tester.takeException(), isNull);
    },
  );
}
