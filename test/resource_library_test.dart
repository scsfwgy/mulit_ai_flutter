import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/chat/widgets/chat_attachments.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/settings/resource_library_screen.dart';

void main() {
  StoredChatFile sample({
    required String name,
    required String mimeType,
    required int messageId,
    required DateTime createdAt,
  }) => StoredChatFile(
    attachment: ChatAttachment(
      name: name,
      fileName: '11111111-1111-1111-1111-111111111111.png',
      mimeType: mimeType,
      size: 2048,
      estimatedTokens: 1,
    ),
    topicId: 7,
    topicTitle: '话题',
    messageId: messageId,
    createdAt: createdAt.millisecondsSinceEpoch,
  );

  test('groups files by local day, newest day first', () {
    final now = DateTime(2026, 10, 24, 16);
    final files = [
      sample(
        name: 'later.png',
        mimeType: 'image/png',
        messageId: 3,
        createdAt: DateTime(2026, 10, 24, 9),
      ),
      sample(
        name: 'yesterday.pdf',
        mimeType: 'application/pdf',
        messageId: 2,
        createdAt: DateTime(2026, 10, 23, 22),
      ),
      sample(
        name: 'earlier.png',
        mimeType: 'image/png',
        messageId: 1,
        createdAt: DateTime(2026, 10, 24, 8),
      ),
      sample(
        name: 'old.bin',
        mimeType: 'application/octet-stream',
        messageId: 4,
        createdAt: DateTime(2026, 10, 1, 12),
      ),
    ];
    final days = groupLibraryFiles(files);
    expect(days.map((day) => day.day), [
      DateTime(2026, 10, 24),
      DateTime(2026, 10, 23),
      DateTime(2026, 10, 1),
    ]);
    expect(days.first.files.map((file) => file.attachment.name), [
      'later.png',
      'earlier.png',
    ]);
    expect(libraryDayLabel(days[0].day, now), T('i18n.today'));
    expect(libraryDayLabel(days[1].day, now), T('i18n.yesterday'));
    expect(libraryDayLabel(days[2].day, now), '2026-10-01');
    expect(libraryShareName('a/b\\c'), 'abc');
    expect(libraryShareName('..'), 'file');
  });

  testWidgets('image opens a preview and long-press can locate the message', (
    tester,
  ) async {
    final image = sample(
      name: 'shot.png',
      mimeType: 'image/png',
      messageId: 8,
      createdAt: DateTime(2026, 10, 24, 9),
    );
    final document = sample(
      name: 'notes.pdf',
      mimeType: 'application/pdf',
      messageId: 9,
      createdAt: DateTime(2026, 10, 24, 8),
    );
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final located = Navigator.of(host).push<StoredChatFile>(
      MaterialPageRoute<StoredChatFile>(
        builder: (_) => ResourceLibraryScreen(
          loadFiles: () async => [image, document],
          shareFile: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('notes.pdf'));
    await tester.pump();
    expect(find.byType(ChatAttachmentPreview), findsNothing);

    await tester.tap(find.text('shot.png'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatAttachmentPreview), findsOneWidget);
    Navigator.of(tester.element(find.byType(ChatAttachmentPreview))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text('notes.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(T('i18n.library_locate')), findsOneWidget);
    expect(find.text(T('i18n.share')), findsOneWidget);
    expect(find.text(T('i18n.library_file_path')), findsNothing);
    await tester.tap(find.text(T('i18n.library_locate')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await located, document);
  });

  testWidgets('desktop file actions use a compact menu beside the row', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final document = sample(
        name: 'notes.pdf',
        mimeType: 'application/pdf',
        messageId: 9,
        createdAt: DateTime(2026, 10, 24, 8),
      );
      StoredChatFile? revealed;
      await tester.pumpWidget(
        MaterialApp(
          home: ResourceLibraryScreen(
            loadFiles: () async => [document],
            shareFile: (_, _) async {},
            revealFile: (file) async => revealed = file,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('notes.pdf'));
      await tester.pump();
      expect(find.byKey(libraryDesktopMenuKey), findsOneWidget);
      expect(
        tester.getSize(find.byKey(libraryDesktopMenuKey)).width,
        DesktopLibraryMenu.width,
      );
      expect(find.text(T('i18n.cancel')), findsNothing);
      expect(find.text(T('i18n.library_locate')), findsOneWidget);
      expect(find.text(T('i18n.share')), findsOneWidget);
      expect(find.text(T('i18n.library_file_path')), findsOneWidget);
      final locate = find.text(T('i18n.library_locate'));
      final locateStyle = DefaultTextStyle.of(tester.element(locate)).style
          .merge(tester.widget<Text>(locate).style);
      expect(locateStyle.decoration, TextDecoration.none);
      await tester.tap(find.text(T('i18n.library_file_path')));
      await tester.pump();
      expect(revealed, document);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
