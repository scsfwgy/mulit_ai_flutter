import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/settings/memory_settings_screen.dart';
import 'package:mulit_ai_flutter/settings/prompt_screen.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

import 'sqflite_stub.dart';

void main() {
  setUpAll(useSqflitePluginFactory);

  testWidgets(
    'settings opens memory through model settings on every platform',
    (tester) async {
      installEmptyDatabaseStub(settings: {memoryEnabledSetting: '1'});
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.tap(find.widgetWithText(IosRow, T('i18n.model_settings')));
      await tester.pumpAndSettle();
      expect(find.byType(ModelSettingsScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(IosRow, T('i18n.memory')));
      await tester.pumpAndSettle();
      expect(find.byType(MemorySettingsScreen), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is IosNavButton && widget.icon == CupertinoIcons.back,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IosRow, T('i18n.memory')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first)
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.all(),
  );

  testWidgets(
    'model settings opens memory independently of prompts and returns',
    (tester) async {
      installEmptyDatabaseStub(
        settings: {
          memoryEnabledSetting: '1',
          memoryInGlobalPromptSetting: '1',
          memoryProfileSetting: '喜欢喝茶',
        },
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: const ModelSettingsScreen()));
      await tester.pumpAndSettle();
      final memoryRow = find.widgetWithText(IosRow, T('i18n.memory'));
      final promptsRow = find.widgetWithText(IosRow, T('i18n.prompts'));
      expect(
        find
            .ancestor(of: memoryRow, matching: find.byType(IosSection))
            .evaluate()
            .single,
        isNot(
          find
              .ancestor(of: promptsRow, matching: find.byType(IosSection))
              .evaluate()
              .single,
        ),
      );
      await tester.tap(memoryRow);
      await tester.pumpAndSettle();
      expect(find.byType(MemorySettingsScreen), findsOneWidget);
      expect(
        tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .map((s) => s.value),
        [true, true],
      );
      expect(find.text('喜欢喝茶'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(T('i18n.memory_edit')));
      await tester.pumpAndSettle();
      expect(find.byType(MemoryEditor), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .controller!
            .text,
        '喜欢喝茶',
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is IosNavButton && widget.icon == CupertinoIcons.back,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MemorySettingsScreen), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is IosNavButton && widget.icon == CupertinoIcons.back,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ModelSettingsScreen), findsOneWidget);
      await tester.tap(promptsRow);
      await tester.pumpAndSettle();
      expect(find.byType(PromptSettingsScreen), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsNothing);
      expect(find.text(T('i18n.memory')), findsNothing);
      await tester.tap(find.text(T('i18n.global_prompt')));
      await tester.pumpAndSettle();
      expect(find.byType(PromptEditor), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsNothing);
      expect(find.text(T('i18n.memory')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'message settings toggles this chat and opens global memory',
    (tester) async {
      installEmptyDatabaseStub(settings: {memoryEnabledSetting: '1'});
      var used = true;
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSettingsScreen(
            chatUsesMemory: () async => used,
            onToggleChatMemory: () async {
              used = !used;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.descendant(
        of: find.widgetWithText(IosRow, T('i18n.memory_chat_toggle')),
        matching: find.byType(CupertinoSwitch),
      );
      expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(used, isFalse);
      await tester.tap(find.byKey(const Key('message-memory-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(MemorySettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'master off preserves the saved chat default but disables its control',
    (tester) async {
      installEmptyDatabaseStub(settings: {memoryInGlobalPromptSetting: '1'});
      await tester.pumpWidget(const MaterialApp(home: MemorySettingsScreen()));
      await tester.pumpAndSettle();
      final switches = tester
          .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
          .toList();
      expect(switches[0].value, isFalse);
      expect(switches[1].value, isTrue);
      expect(switches[1].onChanged, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
