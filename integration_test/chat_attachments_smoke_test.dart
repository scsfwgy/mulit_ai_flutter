import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:mulit_ai_flutter/chat/widgets/chat_composer.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/main.dart' as app;

class _PickerLimits extends ImagePickerPlatform {
  _PickerLimits(this.delegate);
  final ImagePickerPlatform delegate;
  final limits = <int?>[];
  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) {
    limits.add(options.limit);
    return delegate.getMultiImageWithOptions(options: options);
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) => delegate.getImageFromSource(source: source, options: options);
}

/// iOS simulator: native picker results are stubbed, while file IO, SQLite,
/// secure storage, HTTP/SSE and the complete chat UI use their real paths.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('three attachment sources, retry, follow-up, reload and deletion', (
    tester,
  ) async {
    // Keep native keyboard state from overwriting injected test text on refocus.
    binding.testTextInput.register();
    addTearDown(binding.testTextInput.unregister);
    const purchases = MethodChannel('between_models/apple_purchases');
    final messenger = tester.binding.defaultBinaryMessenger;
    final originalPicker = ImagePickerPlatform.instance;
    final pickerLimits = _PickerLimits(originalPicker);
    ImagePickerPlatform.instance = pickerLimits;
    addTearDown(() => ImagePickerPlatform.instance = originalPicker);
    messenger.setMockMethodCallHandler(
      purchases,
      (_) async => {'enabled': false, 'ready': true},
    );
    final store = ChatStore.instance;
    final database = await store.db;
    final saved = <String, String?>{};
    for (final key in [
      'last_chat_selection',
      'search_enabled',
      'voice_auto_read',
      'app_language',
      'app_appearance',
      'app_skin',
      'global_prompt',
    ]) {
      saved[key] = await store.setting(key);
    }
    final existingTopics = (await store.topics()).map((t) => t.id).toSet();
    final temporary = await Directory(
      '${(await getTemporaryDirectory()).path}/attachment-qa-${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    final photo = File('${temporary.path}/qa-photo.png');
    final camera = File('${temporary.path}/qa-camera.png');
    final logo = await rootBundle.load(
      'assets/branding/ai_link_icon_source.png',
    );
    await photo.writeAsBytes(
      logo.buffer.asUint8List(logo.offsetInBytes, logo.lengthInBytes),
    );
    await camera.writeAsBytes(await photo.readAsBytes());
    final notes = File(
      '${temporary.path}/long-file-name-for-layout-and-analysis.csv',
    );
    await notes.writeAsString('category,value\nApples,12\nOranges,8');
    final pdf = File('${temporary.path}/qa-report.pdf');
    await pdf.writeAsString('%PDF-1.4\n%%EOF');
    final unsupported = File('${temporary.path}/qa-unsupported.docx');
    await unsupported.writeAsBytes([80, 75, 3, 4]);
    var selectedFiles = [notes.path];
    var selectedImages = [photo.path];
    var cameraCalls = 0;
    const channels = [
      'dev.flutter.pigeon.image_picker_ios.ImagePickerApi.pickMultiImage',
      'dev.flutter.pigeon.image_picker_ios.ImagePickerApi.pickImage',
      'dev.flutter.pigeon.file_selector_ios.FileSelectorApi.openFile',
    ];
    messenger.setMockMessageHandler(
      channels[0],
      (_) async => const StandardMessageCodec().encodeMessage([selectedImages]),
    );
    messenger.setMockMessageHandler(channels[1], (_) async {
      cameraCalls++;
      return const StandardMessageCodec().encodeMessage([camera.path]);
    });
    messenger.setMockMessageHandler(
      channels[2],
      (_) async => const StandardMessageCodec().encodeMessage([selectedFiles]),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      final title = body['max_tokens'] == 64;
      if (!title) requests.add(body);
      if (!title && requests.length == 1) {
        request.response.statusCode = 400;
        request.response.write(
          '{"error":{"message":"model does not support image inputs"}}',
        );
      } else {
        final answer = title
            ? 'Attachment QA'
            : '## 附件分析\n\n图片与文件已收到。\n\n| 类别 | 数值 |\n| --- | --- |\n| Apples | 12 |\n| Oranges | 8 |';
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.add(
          utf8.encode(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': answer},
                },
              ],
            })}\n\ndata: [DONE]\n\n',
          ),
        );
      }
      await request.response.close();
    });
    int? providerId;
    int? topicId;
    final ownedFiles = <File>[];
    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      // The composer remains busy while its action sheet is open. Its spinner
      // intentionally never settles until a source is picked or cancelled.
      if (find.byType(CupertinoActionSheet).evaluate().isNotEmpty) {
        expect(tester.takeException(), isNull);
        return;
      }
      for (var i = 0; i < 200; i++) {
        final composers = find.byType(ChatComposer).evaluate();
        if (composers.isEmpty ||
            !(composers.single.widget as ChatComposer).pickingAttachment) {
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

    Future<void> pick(String label) async {
      await tester.ensureVisible(find.byIcon(CupertinoIcons.add_circled));
      await tester.tap(find.byIcon(CupertinoIcons.add_circled));
      await settle();
      await tester.tap(find.text(label));
      await settle();
    }

    Future<void> waitForReply(int expectedRequests) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
        if (requests.length >= expectedRequests &&
            !composer.sending &&
            !composer.starting) {
          break;
        }
      }
      await settle();
    }

    try {
      for (final entry in {
        'search_enabled': '0',
        'voice_auto_read': '0',
        'app_language': 'zh',
        'app_appearance': 'light',
        'app_skin': 'ios',
        'global_prompt': '',
      }.entries) {
        await store.saveSetting(entry.key, entry.value);
      }
      providerId = await store.saveProvider(
        ProviderConfig(
          id: 0,
          name: 'Attachment QA service',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'attachment-fixture',
          protocol: ApiProtocol.openAi,
        ),
        apiKey: 'temporary-attachment-key',
      );
      await store.saveLastChatSelection(
        ChatSelection(providerId, 'attachment-fixture'),
      );
      await app.main();
      await settle();
      await binding.convertFlutterSurfaceToImage();
      await binding.takeScreenshot('ios-composer-empty');
      await tester.enterText(
        find.byType(CupertinoTextField).first,
        '输入文字后显示发送',
      );
      await settle();
      expect(find.byIcon(CupertinoIcons.add_circled), findsNothing);
      expect(find.text(T('i18n.send')), findsOneWidget);
      await binding.takeScreenshot('ios-composer-send');
      await tester.enterText(find.byType(CupertinoTextField).first, '');
      await settle();
      await tester.tap(find.byIcon(CupertinoIcons.add_circled));
      await settle();
      expect(find.text(T('i18n.attachment_images')), findsOneWidget);
      expect(find.text(T('i18n.attachment_camera')), findsOneWidget);
      expect(find.text(T('i18n.attachment_files')), findsOneWidget);
      final menuItems = tester.widgetList<CupertinoActionSheetAction>(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.byType(CupertinoActionSheetAction),
        ),
      );
      expect(menuItems.take(3).map((item) => (item.child as Text).data), [
        T('i18n.attachment_camera'),
        T('i18n.attachment_images'),
        T('i18n.attachment_files'),
      ]);
      await binding.takeScreenshot('ios-attachment-menu');
      await tester.tap(find.text(T('i18n.attachment_images')));
      await settle();
      expect(pickerLimits.limits, [9]);
      final firstPhoto = tester
          .widget<ChatComposer>(find.byType(ChatComposer))
          .attachments
          .single;
      expect(firstPhoto.size, lessThan(await photo.length()));
      final photoName = firstPhoto.name;
      await pick(T('i18n.attachment_camera'));
      expect(cameraCalls, 1);
      await pick(T('i18n.attachment_files'));
      selectedFiles = [pdf.path];
      await pick(T('i18n.attachment_files'));
      var composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
      expect(composer.attachments, hasLength(4));
      final removed = composer.attachments.firstWhere(
        (a) => a.name.startsWith('qa-camera.'),
      );
      composer.onRemoveAttachment!(removed);
      await settle();
      expect(
        await (await AttachmentStore.instance.file(removed)).exists(),
        isFalse,
      );
      final retained = tester
          .widget<ChatComposer>(find.byType(ChatComposer))
          .attachments
          .map((a) => a.fileName)
          .toSet();
      selectedImages = List.filled(6, photo.path);
      await pick(T('i18n.attachment_images'));
      expect(pickerLimits.limits, [9, 6]);
      composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
      expect(composer.attachments.length, 9);
      await binding.takeScreenshot('ios-attachment-nine');
      await tester.ensureVisible(find.byIcon(CupertinoIcons.add_circled));
      await tester.tap(find.byIcon(CupertinoIcons.add_circled));
      await settle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.text(T('i18n.attachment_count_limit')), findsOneWidget);
      expect(pickerLimits.limits, [9, 6]);
      final extra = composer.attachments
          .where((a) => !retained.contains(a.fileName))
          .toList();
      for (final attachment in extra) {
        composer.onRemoveAttachment!(attachment);
        await settle();
        expect(
          await (await AttachmentStore.instance.file(attachment)).exists(),
          isFalse,
        );
      }
      selectedFiles = [unsupported.path];
      await pick(T('i18n.attachment_files'));
      composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
      expect(composer.attachments, hasLength(4));
      expect(
        composer.attachments.any(
          (a) =>
              a.name == 'qa-unsupported.docx' &&
              a.mimeType == 'application/octet-stream',
        ),
        isTrue,
      );
      for (final a in composer.attachments) {
        ownedFiles.add(await AttachmentStore.instance.file(a));
      }
      await tester.pump(const Duration(seconds: 5));
      await settle();
      await binding.takeScreenshot('ios-attachment-draft');
      await tester.tap(find.text(T('i18n.send')));
      await waitForReply(1);
      expect(find.text(T('i18n.attachment_model_unsupported')), findsOneWidget);
      topicId = (await store.topics())
          .firstWhere((t) => !existingTopics.contains(t.id))
          .id;
      expect((await store.messages(topicId)).single.attachments, hasLength(4));
      await settle();
      expect(find.text(photoName), findsOneWidget);
      await binding.takeScreenshot('ios-attachment-error');
      await tester.tap(find.text(T('i18n.retry_response')));
      await waitForReply(2);
      expect(requests.length, 2);
      expect(requests.first['messages'], requests.last['messages']);
      expect(
        (await store.messages(topicId)).where((m) => m.role == 'user'),
        hasLength(1),
      );
      await binding.takeScreenshot('ios-attachment-chat');
      await tester.enterText(
        find.byType(CupertinoTextField).first,
        '这张图片里有什么？',
      );
      await settle();
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).controller.text,
        '这张图片里有什么？',
      );
      await tester.tap(find.text(T('i18n.send')));
      await waitForReply(3);
      expect(requests.length, 3);
      expect(requests.last['messages'][0]['content'], hasLength(4));
      expect((await store.messages(topicId)), hasLength(4));
      await tester.pumpWidget(const SizedBox());
      await app.main();
      await settle();
      await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
      await settle();
      final topic = (await store.topics()).firstWhere((t) => t.id == topicId);
      await tester.tap(find.text(topic.title));
      await settle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 500));
      await settle();
      expect(find.text(photoName), findsOneWidget);
      await tester.tap(find.text(photoName));
      await settle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await binding.takeScreenshot('ios-attachment-preview');
      await tester.tap(find.byIcon(CupertinoIcons.back));
      await settle();
      await tester.pumpWidget(const SizedBox());
      await store.deleteTopic(topicId);
      topicId = null;
      for (final f in ownedFiles) {
        expect(await f.exists(), isFalse);
      }
      expect(await photo.exists(), isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox());
      if (topicId != null) await store.deleteTopic(topicId);
      if (providerId != null) await store.deleteProvider(providerId);
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
      for (final channel in channels) {
        messenger.setMockMessageHandler(channel, null);
      }
      messenger.setMockMethodCallHandler(purchases, null);
      await temporary.delete(recursive: true);
      await server.close(force: true);
    }
  });
}
