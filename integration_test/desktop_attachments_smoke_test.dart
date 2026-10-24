import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/chat/widgets/desktop_attachment_drop.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/main.dart' as app;

/// macOS: inject native picker/drop events; use real app, codecs and file IO.
/// Never send a model request or modify existing providers/topics.
class _DesktopTestBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  void scheduleFrame() {
    // macOS may keep the QA window hidden when another app copy is running.
    if (framesEnabled) {
      super.scheduleFrame();
    } else {
      super.scheduleForcedFrame();
    }
  }
}

void main() {
  final binding = _DesktopTestBinding();
  testWidgets(
    'desktop plus opens files directly and native drops share attachment rules',
    (tester) async {
      final store = ChatStore.instance;
      final database = await store.db;
      final saved = <String, String?>{};
      for (final key in ['app_language', 'app_appearance', 'app_skin']) {
        saved[key] = await store.setting(key);
      }
      final root = await Directory(
        '${(await getTemporaryDirectory()).path}/desktop-attachment-qa-${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final text = await File('${root.path}/desktop-notes.txt')
          .writeAsString('Desktop drop test');
      final pdf = await File('${root.path}/desktop-report.pdf')
          .writeAsString('%PDF-1.4\n%%EOF');
      final logo = await rootBundle.load(
        'assets/branding/ai_link_icon_source.png',
      );
      final photo = await File('${root.path}/desktop-photo.png').writeAsBytes(
        logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes),
      );
      const pickerChannel =
          'dev.flutter.pigeon.file_selector_macos.FileSelectorApi.displayOpenPanel';
      final messenger = tester.binding.defaultBinaryMessenger;
      // This flow never needs credentials; avoid touching the user's Keychain.
      const secureStorage = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      messenger.setMockMethodCallHandler(secureStorage, (_) async => null);
      var pickerCalls = 0;
      messenger.setMockMessageHandler(pickerChannel, (_) async {
        pickerCalls++;
        return const StandardMessageCodec().encodeMessage([
          [text.path],
        ]);
      });
      final screenshots = <Map<String, Object>>[];
      binding.reportData = {'screenshots': screenshots};
      Future<void> settle() async {
        await tester.pump(const Duration(milliseconds: 400));
        for (var i = 0; i < 300; i++) {
          final widgets = find.byType(ChatComposer).evaluate();
          if (widgets.isNotEmpty &&
              !(widgets.single.widget as ChatComposer).pickingAttachment) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(tester.takeException(), isNull);
      }

      ChatComposer composer() =>
          tester.widget<ChatComposer>(find.byType(ChatComposer));
      Future<void> event(String method, Object? args) =>
          messenger.handlePlatformMessage(
            'desktop_drop',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
      Future<void> enter() async {
        final point = tester.getCenter(find.byType(DesktopAttachmentDrop));
        await event('entered', [point.dx, point.dy]);
        await tester.pump();
      }

      Future<void> drop(List<Map<String, Object>> items) async {
        await enter();
        await event('performOperation_macos', items);
        await settle();
      }

      Future<void> screenshot(String name) async {
        final finder = find
            .ancestor(
              of: find.byType(DesktopAttachmentDrop),
              matching: find.byType(RepaintBoundary),
            )
            .last;
        final image = await tester
            .renderObject<RenderRepaintBoundary>(finder)
            .toImage(pixelRatio: 1);
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        screenshots.add({
          'screenshotName': name,
          'bytes': data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes)
              .toList(),
        });
        image.dispose();
      }

      try {
        for (final entry in {
          'app_language': 'zh',
          'app_appearance': 'light',
          'app_skin': 'ios',
        }.entries) {
          await store.saveSetting(entry.key, entry.value);
        }
        await app.main();
        debugPrint('Desktop attachment QA: app initialized');
        await settle();
        debugPrint('Desktop attachment QA: chat ready');
        expect(find.byType(DesktopAttachmentDrop), findsOneWidget);
        await tester.tap(find.byIcon(CupertinoIcons.add_circled));
        await settle();
        expect(pickerCalls, 1);
        debugPrint('Desktop attachment QA: direct file selection passed');
        expect(find.byType(CupertinoActionSheet), findsNothing);
        expect(composer().attachments.single.name, 'desktop-notes.txt');
        await enter();
        expect(find.text(T('i18n.attachment_drop_here')), findsOneWidget);
        await screenshot('macos-attachment-drop-hover');
        await event('performOperation_macos', [
          {'path': photo.path, 'isDirectory': false},
          {'path': pdf.path, 'isDirectory': false},
        ]);
        await settle();
        expect(composer().attachments.length, 3);
        expect(
          composer().attachments.firstWhere((a) => a.isImage).size,
          lessThan(await photo.length()),
        );
        Object? imageError;
        final imageFile = await AttachmentStore.instance.file(
          composer().attachments.firstWhere((a) => a.isImage),
        );
        await precacheImage(
          ResizeImage(FileImage(imageFile), width: 256),
          tester.element(find.byType(DesktopAttachmentDrop)),
          onError: (error, _) => imageError = error,
        );
        await tester.pump();
        expect(imageError, isNull);
        await screenshot('macos-attachment-drop-draft');
        debugPrint('Desktop attachment QA: image and PDF drop passed');
        final navigator = Navigator.of(
          tester.element(find.byType(DesktopAttachmentDrop)),
          rootNavigator: true,
        );
        navigator.push(
          CupertinoPageRoute<void>(
            builder: (_) => const CupertinoPageScaffold(
              child: Center(child: Text('Overlay test')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropTarget>(find.byType(DropTarget, skipOffstage: false))
              .enable,
          isFalse,
        );
        navigator.pop();
        await tester.pumpAndSettle();
        expect(
          tester.widget<DropTarget>(find.byType(DropTarget)).enable,
          isTrue,
        );
        await drop([
          {'path': root.path, 'isDirectory': true},
        ]);
        expect(find.text(T('i18n.attachment_drop_files_only')), findsOneWidget);
        expect(composer().attachments.length, 3);
        ScaffoldMessenger.of(tester.element(find.byType(DesktopAttachmentDrop)))
            .clearSnackBars();
        await tester.pumpAndSettle();
        await drop([
          for (var i = 0; i < 7; i++) {'path': text.path},
        ]);
        expect(find.text(T('i18n.attachment_count_limit')), findsOneWidget);
        expect(composer().attachments.length, 3);
        await drop([
          for (var i = 0; i < 6; i++) {'path': text.path},
        ]);
        expect(composer().attachments.length, 9);
        debugPrint('Desktop attachment QA: shared nine-item limit passed');
        final files = composer().attachments.toList();
        for (final attachment in files) {
          composer().onRemoveAttachment!(attachment);
          await settle();
          expect(
            await (await AttachmentStore.instance.file(attachment)).exists(),
            isFalse,
          );
        }
        expect(composer().attachments, isEmpty);
        expect(await photo.exists(), isTrue);
        expect(await text.exists(), isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        messenger.setMockMethodCallHandler(secureStorage, null);
        messenger.setMockMessageHandler(pickerChannel, null);
        for (final entry in saved.entries) {
          if (entry.value == null) {
            await database.delete(
              'settings',
              where: 'key = ?',
              whereArgs: [entry.key],
            );
          } else {
            await store.saveSetting(entry.key, entry.value!);
          }
        }
        await root.delete(recursive: true);
      }
    },
  );
}
