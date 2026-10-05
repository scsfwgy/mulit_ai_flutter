import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/startup_screen.dart';

void main() {
  testWidgets('launch stays visible until preferences and chat are ready', (
    tester,
  ) async {
    final preferences = Completer<void>();
    late VoidCallback ready;
    await tester.pumpWidget(
      CupertinoApp(
        home: StartupScreen(
          initialize: () => preferences.future,
          homeBuilder: (onReady) {
            ready = onReady;
            return const Text('Chat');
          },
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AppLaunchArtwork), findsOneWidget);
    expect(find.text('Chat'), findsNothing);

    preferences.complete();
    await tester.pump();
    expect(find.text('Chat'), findsOneWidget);
    expect(find.byType(AppLaunchArtwork), findsOneWidget);
    ready();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(AppLaunchArtwork), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'fast initialization still leaves time for the launch animation',
    (tester) async {
      late VoidCallback ready;
      await tester.pumpWidget(
        CupertinoApp(
          home: StartupScreen(
            initialize: () async {},
            homeBuilder: (onReady) {
              ready = onReady;
              return const Text('Chat');
            },
          ),
        ),
      );
      await tester.pump();
      ready();
      await tester.pump(const Duration(milliseconds: 899));
      expect(find.byType(AppLaunchArtwork), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.byType(AppLaunchArtwork), findsNothing);
      expect(find.text('Chat'), findsOneWidget);
    },
  );

  testWidgets('storage failure reaches the home error UI and does not hang', (
    tester,
  ) async {
    late VoidCallback ready;
    await tester.pumpWidget(
      CupertinoApp(
        home: StartupScreen(
          initialize: () async => throw StateError('storage unavailable'),
          homeBuilder: (onReady) {
            ready = onReady;
            return const Text('Storage error');
          },
        ),
      ),
    );
    await tester.pump();
    ready();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byType(AppLaunchArtwork), findsNothing);
    expect(find.text('Storage error'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
