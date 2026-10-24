import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/chat/attachment_picker.dart';
import 'package:mulit_ai_flutter/chat/widgets/desktop_attachment_drop.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('desktop_drop');
  Future<void> event(String method, Object? args) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'native file drag highlights chat and forwards files only after drop',
    (tester) async {
      List<DropItem>? files;
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DesktopAttachmentDrop(
                enabled: enabled,
                onDrop: (items) async => files = items,
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      );
      await event('entered', [100.0, 100.0]);
      await tester.pump();
      expect(find.text(T('i18n.attachment_drop_here')), findsOneWidget);
      expect(files, isNull);
      await event('performOperation', ['/tmp/example.txt', '/tmp/image.png']);
      await tester.pump();
      expect(files!.map((f) => f.path), ['/tmp/example.txt', '/tmp/image.png']);
      expect(find.text(T('i18n.attachment_drop_here')), findsNothing);
      await event('entered', [100.0, 100.0]);
      await tester.pump();
      rebuild(() => enabled = false);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(T('i18n.attachment_drop_here')), findsNothing);
      files = null;
      await event('entered', [100.0, 100.0]);
      await event('performOperation', ['/tmp/ignored.txt']);
      expect(files, isNull);
    },
  );

  testWidgets('another route disables the hidden chat drop target', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: DesktopAttachmentDrop(
          enabled: true,
          onDrop: (_) async {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropTarget>(find.byType(DropTarget, skipOffstage: false))
          .enable,
      isFalse,
    );
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<DropTarget>(find.byType(DropTarget)).enable, isTrue);
  });

  for (final fail in [false, true]) {
    test(
      'security-scoped access spans import and releases after failure: $fail',
      () async {
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return true;
        });
        final file = DropItemFile(
          '/tmp/file.txt',
          extraAppleBookmark: Uint8List.fromList([1, 2, 3]),
        );
        final action = importDroppedChatFiles([file], (items) async {
          expect(items.single, same(file));
          expect(calls, ['startAccessingSecurityScopedResource']);
          if (fail) {
            throw const AttachmentException('i18n.attachment_unavailable');
          }
        });
        if (fail) {
          await expectLater(action, throwsA(isA<AttachmentException>()));
        } else {
          await action;
        }
        expect(calls, [
          'startAccessingSecurityScopedResource',
          'stopAccessingSecurityScopedResource',
        ]);
      },
    );
  }

  test('folders and denied bookmarks never reach the importer', () async {
    var imported = false;
    final folder = DropItemDirectory('/tmp/folder', []);
    await expectLater(
      importDroppedChatFiles([folder], (_) async => imported = true),
      throwsA(isA<AttachmentException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    await expectLater(
      importDroppedChatFiles([
        DropItemFile(
          '/tmp/file.txt',
          extraAppleBookmark: Uint8List.fromList([1]),
        ),
      ], (_) async => imported = true),
      throwsA(isA<AttachmentException>()),
    );
    expect(imported, isFalse);
  });
}
