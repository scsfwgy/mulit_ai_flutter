import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/voice_recording_overlay.dart';

void main() {
  test('horizontal release action follows current position including returning to center', () {
    expect(VoiceReleaseAction.fromDrag(-60), VoiceReleaseAction.cancel);
    expect(VoiceReleaseAction.fromDrag(60), VoiceReleaseAction.review);
    for (final distance in [-59.0, 0.0, 59.0]) {
      expect(VoiceReleaseAction.fromDrag(distance), VoiceReleaseAction.send);
    }
  });
  testWidgets('recording overlay follows time and all three release actions', (
    tester,
  ) async {
    final elapsed = ValueNotifier<int>(0);
    final level = ValueNotifier<double>(.2);
    final releaseAction = ValueNotifier<VoiceReleaseAction>(
      VoiceReleaseAction.send,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceRecordingOverlay(
            elapsedMs: elapsed,
            level: level,
            releaseAction: releaseAction,
          ),
        ),
      ),
    );

    expect(find.text('正在录音'), findsOneWidget);
    expect(find.text('00:00.0'), findsOneWidget);
    expect(find.text('松开发送'), findsOneWidget);
    expect(find.text('左滑取消'), findsOneWidget);
    expect(find.text('右滑转文字'), findsOneWidget);

    elapsed.value = 6250;
    level.value = .8;
    releaseAction.value = VoiceReleaseAction.cancel;
    await tester.pump();
    expect(find.text('00:06.2'), findsOneWidget);
    expect(find.text('松开取消录音'), findsOneWidget);
    expect(find.text('松开取消'), findsOneWidget);
    releaseAction.value = VoiceReleaseAction.review;
    await tester.pump();
    expect(find.text('松开转文字'), findsOneWidget);
    expect(find.text('识别后确认发送'), findsOneWidget);
    releaseAction.value = VoiceReleaseAction.send;
    await tester.pump();
    expect(find.text('松开发送'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    elapsed.dispose();
    level.dispose();
    releaseAction.dispose();
  });

  testWidgets('recording popup keeps the original hold and release gesture', (
    tester,
  ) async {
    final elapsed = ValueNotifier<int>(0);
    final level = ValueNotifier<double>(.2);
    final releaseAction = ValueNotifier<VoiceReleaseAction>(
      VoiceReleaseAction.send,
    );
    OverlayEntry? popup;
    var released = false;
    var pressStartX = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Listener(
                onPointerDown: (event) {
                  pressStartX = event.position.dx;
                  popup = OverlayEntry(
                    builder: (_) => VoiceRecordingOverlay(
                      elapsedMs: elapsed,
                      level: level,
                      releaseAction: releaseAction,
                    ),
                  );
                  Overlay.of(context, rootOverlay: true).insert(popup!);
                },
                onPointerMove: (event) => releaseAction.value =
                    VoiceReleaseAction.fromDrag(event.position.dx - pressStartX),
                onPointerUp: (_) {
                  released = true;
                  popup?.remove();
                  popup?.dispose();
                },
                child: const SizedBox(
                  width: 180,
                  height: 54,
                  child: Center(child: Text('Hold')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hold')),
    );
    await tester.pump();
    expect(find.text('正在录音'), findsOneWidget);
    expect(
      DefaultTextStyle.of(tester.element(find.text('正在录音'))).style.decoration,
      TextDecoration.none,
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(find.text('松开取消录音'), findsOneWidget);
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    expect(find.text('松开转文字'), findsOneWidget);
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(find.text('松开发送'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(released, isTrue);
    expect(find.text('正在录音'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    elapsed.dispose();
    level.dispose();
    releaseAction.dispose();
  });
}
