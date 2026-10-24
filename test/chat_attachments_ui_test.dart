import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_error_card.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

void main() {
  testWidgets(
    'right action follows text, clearing, voice mode and reply state',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var sends = 0;
      var adds = 0;
      Future<void> mount({
        bool sending = false,
        bool voice = false,
        List<ChatAttachment> attachments = const [],
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChatComposer(
                controller: controller,
                focusNode: focus,
                voiceMode: voice,
                transcribing: false,
                voicePointerDown: false,
                sending: sending,
                starting: false,
                recording: false,
                hasProviders: true,
                onToggleVoiceMode: () {},
                onVoiceDown: (_) {},
                onVoiceMove: (_) {},
                onVoiceUp: (_) {},
                onVoiceCancel: (_) {},
                onSend: () => sends++,
                onStop: () {},
                onAddAttachment: () => adds++,
                attachments: attachments,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await mount();
      expect(find.text(T('i18n.send')), findsNothing);
      expect(
        tester.getCenter(find.byIcon(CupertinoIcons.mic)).dx,
        lessThan(tester.getCenter(find.byType(CupertinoTextField)).dx),
      );
      expect(
        tester.getCenter(find.byIcon(CupertinoIcons.add_circled)).dx,
        greaterThan(tester.getCenter(find.byType(CupertinoTextField)).dx),
      );
      await tester.enterText(find.byType(CupertinoTextField), 'hello');
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.add_circled), findsNothing);
      await tester.tap(find.text(T('i18n.send')));
      expect(sends, 1);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sends, 2);
      controller.clear();
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.add_circled), findsOneWidget);
      controller.text = '  ';
      await tester.pump();
      expect(find.text(T('i18n.send')), findsNothing);
      controller.text = 'transcribed text';
      await tester.pump();
      expect(find.text(T('i18n.send')), findsOneWidget);
      await mount(sending: true);
      expect(find.byIcon(CupertinoIcons.stop_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.add_circled), findsNothing);
      await mount(voice: true);
      expect(find.byIcon(CupertinoIcons.keyboard), findsOneWidget);
      expect(find.text(T('i18n.send')), findsNothing);
      controller.clear();
      await mount(
        attachments: [
          const ChatAttachment(
            name: 'file.pdf',
            fileName: '',
            mimeType: 'application/pdf',
            size: 20,
            estimatedTokens: 4096,
          ),
        ],
      );
      expect(find.text(T('i18n.send')), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(CupertinoIcons.add_circled)).dy,
        lessThan(tester.getCenter(find.text(T('i18n.send'))).dy),
      );
      await tester.tap(find.byIcon(CupertinoIcons.add_circled));
      expect(adds, 1);
    },
  );

  for (final language in [AppLanguage.zh, AppLanguage.zhTW, AppLanguage.en]) {
    testWidgets(
      'composer supports attachments on narrow screens with keyboard: $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 580);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        addTearDown(tester.view.reset);
        final prefs = AppPreferences.instance;
        prefs.language = language;
        prefs.appearance = AppAppearance.dark;
        addTearDown(() {
          prefs.language = AppLanguage.zh;
          prefs.appearance = AppAppearance.system;
        });
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        var added = false;
        var removed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
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
                  onAddAttachment: () => added = true,
                  onRemoveAttachment: (_) => removed = true,
                  attachments: [
                    for (var i = 0; i < 9; i++)
                      ChatAttachment(
                        name: 'very-long-document-name-$i.pdf',
                        fileName: '',
                        mimeType: 'application/pdf',
                        size: 1024,
                        estimatedTokens: 4096,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(T('i18n.attachment_send_notice')), findsOneWidget);
        expect(find.textContaining('i18n.'), findsNothing);
        await tester.ensureVisible(find.byIcon(CupertinoIcons.add_circled));
        await tester.tap(find.byIcon(CupertinoIcons.add_circled));
        expect(added, isTrue);
        await tester.ensureVisible(
          find.byIcon(CupertinoIcons.xmark_circle_fill).first,
        );
        await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill).first);
        expect(removed, isTrue);
      },
    );
  }

  testWidgets(
    'unsupported attachment errors allow explicit retry and model switching',
    (tester) async {
      var retried = false;
      var switched = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatErrorCard(
              messageKey: 'i18n.attachment_model_unsupported',
              action: ChatErrorAction.model,
              canRetryFromLastUser: true,
              onCheckProvider: () {},
              onCheckSearch: () {},
              onRetry: () => retried = true,
              onAdjustContext: () {},
              onNewTopic: () {},
              onChangeModel: () => switched = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text(T('i18n.retry_response')));
      await tester.tap(find.text(T('i18n.switch_model')));
      expect(retried, isTrue);
      expect(switched, isTrue);
    },
  );
}
