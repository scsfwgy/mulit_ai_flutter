import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_message_meta.dart';
import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

void main() {
  testWidgets(
    'copy, speech and stop have larger touch areas and accessible labels',
    (tester) async {
      AppPreferences.instance.simpleMessageInfo = false;
      final input = TextEditingController();
      final focus = FocusNode();
      addTearDown(input.dispose);
      addTearDown(focus.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ChatMessageMeta(
                  assistant: true,
                  content: 'Hello',
                  onCopy: () {},
                  onSpeak: () {},
                ),
                ChatComposer(
                  controller: input,
                  focusNode: focus,
                  voiceMode: false,
                  transcribing: false,
                  voicePointerDown: false,
                  sending: true,
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
                ),
              ],
            ),
          ),
        ),
      );
      for (final icon in [
        CupertinoIcons.doc_on_doc,
        CupertinoIcons.speaker_2,
        CupertinoIcons.stop_fill,
      ]) {
        final button = find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(CupertinoButton),
        );
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(find.bySemanticsLabel(T('i18n.stop_generation')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
