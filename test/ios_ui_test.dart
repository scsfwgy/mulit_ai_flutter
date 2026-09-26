import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/provider_screen.dart';

void main() {
  testWidgets('empty custom provider can switch directly to JSON import', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ProviderEditor()));

    expect(find.byType(CupertinoSlidingSegmentedControl<bool>), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsWidgets);
    await tester.tap(find.text('JSON'));
    await tester.pumpAndSettle();

    final jsonField = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).first,
    );
    expect(jsonField.controller?.text, contains('"protocol": "openai_chat"'));
    expect(find.text('完整配置 JSON'), findsOneWidget);
  });

  testWidgets('all provider logos render from bundled assets', (tester) async {
    for (final preset in providerPresets) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SvgPicture.asset(preset.iconAsset))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: preset.id);
    }
  });
}
