import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';

void main() {
  for (final outcome in ['success', 'false', 'exception']) {
    testWidgets('wish wall opens in the system browser: $outcome', (
      tester,
    ) async {
      Map<dynamic, dynamic>? arguments;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method != 'launch') return null;
        arguments = call.arguments as Map;
        if (outcome == 'exception') throw PlatformException(code: 'no_browser');
        return outcome == 'success';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('心愿墙'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('心愿墙'));
      await tester.pumpAndSettle();
      expect(arguments?['url'], 'https://www.tools24.uk/app/ai-link/wishes');
      expect(arguments?['useWebView'], false);
      expect(arguments?['useSafariVC'], false);
      expect(
        find.text('无法打开浏览器'),
        outcome == 'success' ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
