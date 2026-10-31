import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_screen.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/chat/chat_context_screen.dart';

import 'sqflite_stub.dart';

void main() {
  setUpAll(useSqflitePluginFactory);
  testWidgets('settings switch defaults off and persists a user toggle', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    AppPreferences.instance.agentEnabled = false;
    await tester.pumpWidget(const MaterialApp(home: AgentSettingsScreen()));
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
