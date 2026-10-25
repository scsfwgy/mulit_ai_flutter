import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/chat/desktop_chat.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/settings/memory_settings_screen.dart';
import 'package:mulit_ai_flutter/chat/topic_screen.dart';

import 'sqflite_stub.dart';

void main() {
  setUpAll(useSqflitePluginFactory);

  testWidgets(
    'desktop settings keeps topics and returns through the phone hierarchy',
    (tester) async {
      installEmptyDatabaseStub();
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopChatLayout(
            showSidebar: true,
            sidebar: TopicScreen(
              persistent: true,
              onClose: () {},
              onSelect: (_) {},
              onNew: () {},
              onSettings: () => navigator.currentState!.push(
                appPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              onChanged: () {},
            ),
            chat: Navigator(
              key: navigator,
              onGenerateRoute: (_) => appPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('chat')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sidebarState = tester.state(find.byType(TopicScreen));
      await tester.tap(
        find.descendant(
          of: find.byType(TopicScreen),
          matching: find.text(T('i18n.settings')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.state(find.byType(TopicScreen)), same(sidebarState));
      expect(find.text(T('i18n.model_settings')), findsOneWidget);
      await tester.tap(find.widgetWithText(IosRow, T('i18n.model_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(IosRow, T('i18n.memory')));
      await tester.pumpAndSettle();
      expect(find.byType(MemorySettingsScreen), findsOneWidget);
      final back = find.byWidgetPredicate(
        (widget) =>
            widget is IosNavButton && widget.icon == CupertinoIcons.back,
      );
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(ModelSettingsScreen), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);
      expect(tester.state(find.byType(TopicScreen)), same(sidebarState));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('desktop pages open and close without slide transitions', (
    tester,
  ) async {
    final route = appPageRoute<void>(builder: (_) => const Text('page'));
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );
    Navigator.of(homeContext).push(route);
    await tester.pump();
    expect(find.text('page'), findsOneWidget);
    Navigator.of(homeContext).pop();
    await tester.pump();
    expect(find.text('page'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('phone pages retain Cupertino transitions', (tester) async {
    final route = appPageRoute<void>(builder: (_) => const Text('page'));
    expect(route, isA<CupertinoPageRoute<void>>());
    expect(route.transitionDuration, isNot(Duration.zero));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('desktop action menus appear centrally and dismiss immediately', (
    tester,
  ) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    showAppModalPopup<void>(
      context: homeContext,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(homeContext).pop(),
            child: const Text('desktop option'),
          ),
        ],
      ),
    );
    await tester.pump();
    final sheet = tester.getRect(find.byType(CupertinoActionSheet));
    expect(sheet.center.dx, closeTo(400, 1));
    expect(sheet.center.dy, closeTo(300, 1));
    expect(sheet.width, lessThanOrEqualTo(560));
    await tester.tap(find.text('desktop option'));
    await tester.pump();
    expect(find.text('desktop option'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Mac settings does not offer phone/watch pairing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text('手表'), findsNothing);
    expect(find.text(T('i18n.model_settings')), findsOneWidget);
    expect(find.text(T('i18n.general')), findsOneWidget);
    expect(supportsWatchCompanion, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('mobile settings retains watch pairing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text('手表'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Enter sends, Shift+Enter edits, IME Enter does not send', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var sends = 0;
    var newTopics = 0;
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopChatKeyboard(
          controller: controller,
          inputFocus: focus,
          onSend: () => sends++,
          onNew: () => newTopics++,
          onSettings: () => settings++,
          child: Scaffold(
            body: CupertinoTextField(
              controller: controller,
              focusNode: focus,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(sends, 1);
    controller.value = const TextEditingValue(
      text: '拼音',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 1);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(sends, 2);
    expect(newTopics, 1);
    expect(settings, 1);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Windows uses Control for desktop shortcuts', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    var sends = 0;
    var newTopics = 0;
    var settings = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopChatKeyboard(
          controller: controller,
          inputFocus: focus,
          onSend: () => sends++,
          onNew: () => newTopics++,
          onSettings: () => settings++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(newTopics, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(newTopics, 1);
    expect(settings, 1);
    expect(sends, 1);
    expect(desktopUsesControlShortcuts(TargetPlatform.linux), isTrue);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Windows has no camera import', (tester) async {
    expect(supportsQrScan, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Linux has no camera import', (tester) async {
    expect(supportsQrScan, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('macOS keeps camera import', (tester) async {
    expect(supportsQrScan, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('resizing between sidebar and drawer preserves chat state', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'draft');
    addTearDown(controller.dispose);
    var wide = true;
    late StateSetter resize;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            resize = setState;
            return DesktopChatLayout(
              showSidebar: wide,
              sidebar: const Text('sidebar'),
              chat: CupertinoTextField(
                key: const ValueKey('chat'),
                controller: controller,
              ),
            );
          },
        ),
      ),
    );
    final before = tester.state(find.byType(CupertinoTextField));
    resize(() => wide = false);
    await tester.pump();
    expect(find.text('sidebar'), findsNothing);
    expect(tester.state(find.byType(CupertinoTextField)), same(before));
    expect(controller.text, 'draft');
    await tester.pumpWidget(const SizedBox());
  });
}
