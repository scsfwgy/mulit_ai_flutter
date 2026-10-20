// Opt-in capture of the production ProviderScreen, with an empty test database.
// AI_LINK_CAPTURE_DIR=/absolute/output flutter test test/app_store_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/provider/provider_screen.dart';

import 'sqflite_stub.dart';

void main() {
  final output = Platform.environment['AI_LINK_CAPTURE_DIR'];
  setUpAll(useSqflitePluginFactory);
  testWidgets('capture actual provider catalog without saved credentials', (
    tester,
  ) async {
    installEmptyDatabaseStub();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'StoreCaptureSans': '/System/Library/Fonts/SFNS.ttf',
        'StoreCaptureCJK': '/System/Library/Fonts/Hiragino Sans GB.ttc',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    });
    const captureStyle = TextStyle(
      fontFamily: 'StoreCaptureSans',
      fontFamilyFallback: ['StoreCaptureCJK'],
    );
    for (final device in {
      'phone': const Size(402, 874),
      'ipad': const Size(1376, 1032),
    }.entries) {
      tester.view.physicalSize = device.value * (device.key == 'phone' ? 3 : 2);
      tester.view.devicePixelRatio = device.key == 'phone' ? 3 : 2;
      const key = ValueKey('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.light,
              fontFamily: 'StoreCaptureSans',
              fontFamilyFallback: ['StoreCaptureCJK'],
            ),
            builder: (context, child) => CupertinoTheme(
              data: const CupertinoThemeData(
                brightness: Brightness.light,
                textTheme: CupertinoTextThemeData(textStyle: captureStyle),
              ),
              child: child!,
            ),
            home: const ProviderScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      final heading = find.text(T('i18n.china_providers'));
      list.position.jumpTo(
        list.position.pixels + tester.getTopLeft(heading).dy - 65,
      );
      await tester.pumpAndSettle();
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text(T('i18n.custom_api_json_import')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        // Capture the list viewport, excluding navigation and system chrome.
        final image = await (boundary.debugLayer! as OffsetLayer).toImage(
          Rect.fromLTWH(0, 54, device.value.width, device.value.height - 54),
          pixelRatio: tester.view.devicePixelRatio,
        );
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await Directory(output!).create(recursive: true);
        await File('$output/providers-${device.key}.png')
            .writeAsBytes(data.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
    debugDefaultTargetPlatformOverride = null;
  }, skip: output == null);
}
