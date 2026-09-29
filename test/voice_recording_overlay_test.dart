import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/voice_recording_overlay.dart';

void main() {
  testWidgets('recording overlay follows elapsed time and swipe cancel state', (
    tester,
  ) async {
    final elapsed = ValueNotifier<int>(0);
    final level = ValueNotifier<double>(.2);
    final cancelling = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceRecordingOverlay(
            elapsedMs: elapsed,
            level: level,
            cancelling: cancelling,
          ),
        ),
      ),
    );

    expect(find.text('正在录音'), findsOneWidget);
    expect(find.text('00:00.0'), findsOneWidget);
    expect(find.text('松开转写 · 上滑取消'), findsOneWidget);

    elapsed.value = 6250;
    level.value = .8;
    cancelling.value = true;
    await tester.pump();
    expect(find.text('00:06.2'), findsOneWidget);
    expect(find.text('松开取消录音'), findsOneWidget);
    expect(find.text('松开取消'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    elapsed.dispose();
    level.dispose();
    cancelling.dispose();
  });

  testWidgets('recording popup keeps the original hold and release gesture', (
    tester,
  ) async {
    final elapsed = ValueNotifier<int>(0);
    final level = ValueNotifier<double>(.2);
    final cancelling = ValueNotifier<bool>(false);
    OverlayEntry? popup;
    var released = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Listener(
                onPointerDown: (_) {
                  popup = OverlayEntry(
                    builder: (_) => VoiceRecordingOverlay(
                      elapsedMs: elapsed,
                      level: level,
                      cancelling: cancelling,
                    ),
                  );
                  Overlay.of(context, rootOverlay: true).insert(popup!);
                },
                onPointerMove: (event) => cancelling.value = true,
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
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.text('松开取消录音'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(released, isTrue);
    expect(find.text('正在录音'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    elapsed.dispose();
    level.dispose();
    cancelling.dispose();
  });
}
