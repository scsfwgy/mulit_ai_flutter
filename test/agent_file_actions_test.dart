import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/agent/agent_result_actions.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/file_actions.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:path/path.dart' as p;

void main() {
  test('named copies retain Chinese filenames, isolate deliveries and stay inside the task directory', () async {
    final task = await Directory.systemTemp.createTemp('agent-file-names-');
    try {
      final source = await File(p.join(task.path, '0.pdf'))
          .writeAsBytes([37, 80, 68, 70]);
      final copy = await namedAgentFile(source, '调研报告 2026.pdf');
      expect(p.basename(copy.path), '调研报告 2026.pdf');
      expect(p.isWithin(task.path, copy.path), true);
      expect(await copy.readAsBytes(), await source.readAsBytes());
      final another = await namedAgentFile(source, '调研报告 2026.pdf');
      expect(another.path, isNot(copy.path));
      expect(p.basename(source.path), '0.pdf');
      final safe = await namedAgentFile(source, '../目录/报告.pdf');
      expect(p.isWithin(task.path, safe.path), true);
      expect(p.basename(safe.path), '..目录报告.pdf');
      await expectLater(namedAgentFile(source, '..'), throwsFormatException);
      await expectLater(
        revealFileInManager(File(p.join(task.path, 'missing.pdf'))),
        throwsA(isA<AttachmentException>()),
      );
    } finally {
      await task.delete(recursive: true);
    }
  });

  testWidgets(
    'mobile share passes the original physical basename to the native plugin',
    (tester) async {
      final task = await tester.runAsync(
        () => Directory.systemTemp.createTemp('agent-native-share-'),
      );
      addTearDown(() => task!.delete(recursive: true));
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      Map<dynamic, dynamic>? arguments;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'share');
            arguments = call.arguments as Map;
            return 'dev.fluttercommunity.plus/share/unavailable';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      late BuildContext anchor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                anchor = context;
                return const SizedBox(width: 120, height: 40);
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final source = await File(p.join(task!.path, '17.pdf'))
            .writeAsBytes([37, 80, 68, 70]);
        await openOrShareAgentFile(anchor, source, '原始文件名.pdf');
        final path = (arguments!['paths'] as List).single as String;
        expect(p.basename(path), '原始文件名.pdf');
        expect(await File(path).readAsBytes(), await source.readAsBytes());
        expect(arguments!['mimeTypes'], ['application/pdf']);
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop files use a folder button and mobile files use share',
    (tester) async {
      final desktop = [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ].contains(defaultTargetPlatform);
      var invoked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgentFileActionButton(onPressed: () => invoked++),
          ),
        ),
      );
      expect(
        find.byIcon(desktop ? CupertinoIcons.folder : CupertinoIcons.share),
        findsOneWidget,
      );
      expect(
        find.byTooltip(T(desktop ? 'i18n.agent_open_folder' : 'i18n.share')),
        findsOneWidget,
      );
      await tester.tap(find.byType(CupertinoButton));
      expect(invoked, 1);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}
