import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_feature_hints.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

void main() {
  for (final keyboard in [false, true]) {
    testWidgets(
      'feature hints stay below the field and above keyboard ($keyboard)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 300 : 0);
        addTearDown(tester.view.reset);
        if (keyboard) {
          tester.platformDispatcher.textScaleFactorTestValue = 1.8;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox()),
                  ChatComposer(
                    controller: controller,
                    focusNode: focus,
                    voiceMode: false,
                    transcribing: false,
                    voicePointerDown: false,
                    sending: false,
                    starting: false,
                    recording: false,
                    hasProviders: true,
                    onToggleVoiceMode: () {},
                    onVoiceDown: (_) {},
                    onVoiceMove: (_) {},
                    onVoiceUp: (_) {},
                    onVoiceCancel: (_) {},
                    onSend: () {},
                    onStop: () {},
                    featureHints: const ChatFeatureHints(
                      search: true,
                      readAloud: true,
                      agent: true,
                      memory: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final field = tester.getRect(find.byType(CupertinoTextField));
        final hints = tester.getRect(
          find.byKey(const Key('chat-feature-hints')),
        );
        final search = tester.getRect(find.byIcon(CupertinoIcons.globe));
        final composer = tester.getRect(find.byType(ChatComposer));
        expect(hints.top, greaterThanOrEqualTo(field.bottom));
        expect(search.left, closeTo(field.left, 1));
        expect(hints.bottom, lessThanOrEqualTo(composer.bottom));
        expect(composer.bottom, lessThanOrEqualTo(keyboard ? 500 : 800));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('all disabled hints take no extra composer space', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatFeatureHints(
          search: false,
          readAloud: false,
          agent: false,
          memory: false,
        ),
      ),
    );
    expect(find.byKey(const Key('chat-feature-hints')), findsNothing);
  });
  testWidgets('only enabled features appear as small wrapping labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatFeatureHints(
                search: true,
                readAloud: true,
                agent: true,
                memory: true,
              ),
            ],
          ),
        ),
      ),
    );
    for (final key in [
      'i18n.chat_hint_search',
      'i18n.chat_hint_read_aloud',
      'i18n.agent_title',
      'i18n.chat_hint_memory',
    ]) {
      expect(find.text(T(key)), findsOneWidget);
      expect(tester.widget<Text>(find.text(T(key))).style!.fontSize, 11);
    }
    expect(find.byType(CupertinoButton), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('chat-feature-hints'))).height,
      lessThan(50),
    );
    final searchIcon = tester.getRect(find.byIcon(CupertinoIcons.globe));
    final searchText = tester.getRect(find.text(T('i18n.chat_hint_search')));
    final agentText = tester.getRect(find.text(T('i18n.agent_title')));
    expect((searchIcon.center.dy - searchText.center.dy).abs(), lessThan(1));
    expect((searchText.center.dy - agentText.center.dy).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatFeatureHints(
          search: false,
          readAloud: false,
          agent: true,
          memory: false,
        ),
      ),
    );
    expect(find.text(T('i18n.agent_title')), findsOneWidget);
    expect(find.text(T('i18n.chat_hint_memory')), findsNothing);
  });
}
