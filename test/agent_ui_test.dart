import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_screen.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

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

  testWidgets('disabled tasks are readable but cannot start', (tester) async {
    installEmptyDatabaseStub();
    AppPreferences.instance.agentEnabled = false;
    await tester.pumpWidget(const MaterialApp(home: AgentScreen()));
    await tester.pumpAndSettle();
    expect(find.text(T('i18n.agent_disabled')), findsOneWidget);
    final button = tester.widget<CupertinoButton>(
      find.widgetWithText(CupertinoButton, T('i18n.agent_start')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
