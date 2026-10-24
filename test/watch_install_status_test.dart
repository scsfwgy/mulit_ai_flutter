import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/watch/watch_settings_screen.dart';

import 'package:sqflite/sqflite.dart';

import 'sqflite_stub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;
  for (final reachable in [false, true]) {
    testWidgets(
      'paired installed watch does not wait for reachability=$reachable',
      (tester) async {
        installEmptyDatabaseStub();
        const channel = MethodChannel('between_models/companion_install');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'platform': 'apple',
            'connected': 1,
            'installed': true,
            'reachable': reachable,
            'missing': [],
          },
        );
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(const MaterialApp(home: WatchSettingsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('已配对，手表应用已安装'), findsOneWidget);
        expect(find.textContaining('等待连接'), findsNothing);
      },
    );
  }
}
