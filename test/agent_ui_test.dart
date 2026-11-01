import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_screen.dart';
import 'package:mulit_ai_flutter/agent/agent_runner.dart';
import 'package:mulit_ai_flutter/agent/agent_task_actions.dart';
import 'package:mulit_ai_flutter/agent/agent_result_actions.dart';
import 'package:mulit_ai_flutter/agent/agent_store.dart';
import 'package:mulit_ai_flutter/api/tool_call.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';

import 'sqflite_stub.dart';

void main() {
  setUpAll(useSqflitePluginFactory);
  testWidgets(
    'paused task accepts reviewed instructions before resuming once',
    (tester) async {
      AppPreferences.instance.agentEnabled = true;
      addTearDown(() => AppPreferences.instance.agentEnabled = false);
      final task = AgentTask(
        providerId: 1,
        model: 'test',
        protocol: ApiProtocol.openAi,
        goal: 'Original',
        systemPrompt: '',
      );
      installEmptyDatabaseStub(
        settings: {'agent_task:${task.id}': jsonEncode(task.toJson())},
      );
      var resumed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentTaskActions(task: task, onResume: () => resumed++),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('agent-refine')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('agent-refine-input')),
        'Use recent sources',
      );
      expect(resumed, 0);
      expect(task.instructions, isEmpty);
      await tester.tap(find.text(T('i18n.agent_refine_resume')));
      await tester.pumpAndSettle();
      expect(resumed, 1);
      expect(task.instructions, ['Use recent sources']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving a note opens an editable preview before any write', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    final task =
        AgentTask(
            providerId: 1,
            model: 'test',
            protocol: ApiProtocol.openAi,
            goal: 'Report',
            systemPrompt: '',
          )
          ..answer = 'Reviewed content'
          ..status = 'completed';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentResultActions(task: task)),
      ),
    );
    await tester.tap(find.text(T('i18n.agent_save_note')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(CupertinoTextField, 'Report.md'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(CupertinoTextField, 'Reviewed content'),
      findsOneWidget,
    );
    expect(find.text(T('i18n.agent_select_project')), findsOneWidget);
    expect(find.text(T('i18n.agent_note_detail')), findsOneWidget);
    await tester.tap(find.text(T('i18n.agent_select_project')));
    await tester.pumpAndSettle();
    expect(find.text(T('i18n.ungrouped_chats')), findsNothing);
    expect(find.text(T('i18n.new_project')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'returning from a resumed task keeps it running until manual pause',
    (tester) async {
      installEmptyDatabaseStub(settings: {'agent_enabled': '1'});
      AppPreferences.instance.agentEnabled = true;
      final gate = Completer<void>();
      const channel = MethodChannel('between_models/agent_background');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'begin') await gate.future;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final task = AgentTask(
        providerId: 1,
        model: 'test',
        protocol: ApiProtocol.openAi,
        goal: 'Resume',
        systemPrompt: '',
      )..finalReady = true;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => AgentTaskScreen(task: task)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(T('i18n.agent_resume')));
      await tester.pump();
      final runner = AgentRunner.active!;
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(AgentRunner.active, same(runner));
      void listener() {}
      expect(() => runner.addListener(listener), returnsNormally);
      runner.removeListener(listener);
      // Stop explicitly after checking navigation preserved the live runner.
      runner.pause();
      gate.complete();
      for (var i = 0; i < 30 && AgentRunner.isBusy; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(AgentRunner.isBusy, false);
      expect(task.status, 'paused');
      expect(() => runner.addListener(() {}), throwsFlutterError);
      AppPreferences.instance.agentEnabled = false;
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Agent executes tools in the background without a native handler',
    (tester) async {
      installEmptyDatabaseStub();
      const channel = MethodChannel('between_models/agent_background');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final task = AgentTask(
        providerId: 1,
        model: 'test',
        protocol: ApiProtocol.openAi,
        goal: 'Background task',
        systemPrompt: '',
      );
      final response = Completer<ModelToolTurn>();
      var executed = 0;
      late final AgentRunner runner;
      runner = AgentRunner(
        repository: AgentStore(),
        allowed: () async => true,
        turn: (_, _) => response.future,
        execute: (_, _, _) async {
          executed++;
          runner.pause();
          return {};
        },
      );
      addTearDown(runner.dispose);
      final run = runner.run(task);
      await tester.pumpWidget(MaterialApp(home: AgentTaskScreen(task: task)));
      for (var i = 0; i < 10 && task.status != 'running'; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(task.status, 'running');
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      response.complete(
        ModelToolTurn(
          {'role': 'assistant', 'content': null},
          '',
          [
            ModelToolCall('background', 'read_webpage', {
              'url': 'https://example.com',
            }),
          ],
          1,
          1,
        ),
      );
      for (var i = 0; i < 30 && AgentRunner.isBusy; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(AgentRunner.isBusy, false);
      await run;
      expect(executed, 1);
      expect(task.status, 'paused');
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('settings switch defaults off and persists a user toggle', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    AppPreferences.instance.agentEnabled = false;
    await tester.pumpWidget(const MaterialApp(home: AgentSettingsScreen()));
    expect(find.text(T('i18n.agent_settings_detail')), findsOneWidget);
    final toggle = find.byKey(const Key('agent-enable'));
    expect(tester.widget<CupertinoSwitch>(toggle).value, false);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(toggle).value, true);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(toggle).value, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('message settings shows status and opens Agent management', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    final prefs = AppPreferences.instance;
    prefs.agentEnabled = false;
    await tester.pumpWidget(const MaterialApp(home: MessageSettingsScreen()));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('message-agent-settings'));
    await tester.ensureVisible(row);
    expect(
      find.descendant(of: row, matching: find.text(T('i18n.agent_off'))),
      findsOneWidget,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(AgentSettingsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('agent-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.back).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row, matching: find.text(T('i18n.agent_on'))),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agent context selection leaves ordinary chat budget unchanged', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    final prefs = AppPreferences.instance;
    prefs.contextWindowTokens = 8192;
    prefs.agentContextWindowTokens = 32768;
    await tester.pumpWidget(
      const MaterialApp(home: ChatContextScreen(forAgent: true)),
    );
    await tester.tap(find.text('64K Token'));
    await tester.pumpAndSettle();
    expect(prefs.agentContextWindowTokens, 65536);
    expect(prefs.contextWindowTokens, 8192);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task history remains readable with Agent disabled', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    AppPreferences.instance.agentEnabled = false;
    await tester.pumpWidget(const MaterialApp(home: AgentScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-goal')), findsNothing);
    expect(find.text(T('i18n.agent_chat_detail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
