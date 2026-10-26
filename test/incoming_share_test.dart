import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/incoming_share.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AttachmentStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('incoming-share-test-');
    store = AttachmentStore(Directory('${root.path}/owned'));
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'shared text and arbitrary files use private attachment copies',
    () async {
      final text = await File('${root.path}/quote.txt')
          .writeAsString('Shared quote');
      final file = await File('${root.path}/report.docx')
          .writeAsBytes([80, 75, 0, 1]);
      final share = IncomingShare('share-1', [
        (path: text.path, name: 'Shared text.txt'),
        (path: file.path, name: 'report.docx'),
      ]);
      final imported = await share.import(store);
      expect(imported.first.isText, isTrue);
      expect(imported.last.isGenericFile, isTrue);
      await store.delete(imported);
      expect(await text.readAsString(), 'Shared quote');
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'failed batch removes only imported copies and preserves the inbox',
    () async {
      final text = await File('${root.path}/quote.txt').writeAsString('keep');
      final share = IncomingShare('share-2', [
        (path: text.path, name: 'quote.txt'),
        (path: '${root.path}/missing', name: 'missing.pdf'),
      ]);
      await expectLater(
        share.import(store),
        throwsA(isA<AttachmentException>()),
      );
      expect(await (await store.directory).list().toList(), isEmpty);
      expect(await text.readAsString(), 'keep');
    },
  );

  test('rejects empty, oversized batches and native copy failures', () async {
    for (final share in [
      const IncomingShare('empty', []),
      IncomingShare(
        'many',
        List.generate(10, (_) => (path: '/unused', name: 'file')),
      ),
      const IncomingShare('failed', [], error: 'i18n.attachment_too_large'),
    ]) {
      await expectLater(
        share.import(store),
        throwsA(isA<AttachmentException>()),
      );
    }
    expect(await (await store.directory).exists(), isFalse);
  });

  test(
    'peek does not acknowledge until the caller has accepted the share',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(IncomingShare.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'peek') {
          return {
            'id': 'pending',
            'files': [
              {'path': '/inbox/text', 'name': 'quote.txt'},
            ],
          };
        }
        expect(call.arguments, {'id': 'pending'});
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(IncomingShare.channel, null),
      );
      final share = (await IncomingShare.peek())!;
      expect(calls, ['peek']);
      expect(share.files.single.name, 'quote.txt');
      await share.acknowledge();
      expect(calls, ['peek', 'ack']);
    },
  );
}
