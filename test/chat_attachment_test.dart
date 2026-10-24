import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/api/api_client.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/core/data.dart';

void main() {
  late Directory root;
  late AttachmentStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-link-attachments-');
    store = AttachmentStore(Directory('${root.path}/owned'));
  });
  tearDown(() async => root.delete(recursive: true));

  Future<ChatAttachment> imported(String name, List<int> bytes) async {
    final original = File('${root.path}/$name');
    await original.writeAsBytes(bytes);
    return store.importFile(original.path, name);
  }

  test(
    'imports private copies, preserves metadata, and deletes only the copy',
    () async {
      final attachment = await imported('notes.md', utf8.encode('hello 世界'));
      expect(attachment.isText, isTrue);
      expect(attachment.estimatedTokens, greaterThan(0));
      final restored = ChatAttachment.decode(
        ChatAttachment.encode([attachment]),
      ).single;
      expect(restored.toJson(), attachment.toJson());
      expect(utf8.decode(await store.read(restored)), 'hello 世界');
      await store.delete([restored]);
      expect(await File('${root.path}/notes.md').exists(), isTrue);
      expect(await (await store.file(restored)).exists(), isFalse);
      expect(ChatAttachment.decode(null), isEmpty);
    },
  );

  test(
    'accepts any non-empty file and still rejects empty or oversize files',
    () async {
      final docx = await imported('office.docx', [80, 75, 3, 4, 20]);
      expect(docx.isGenericFile, isTrue);
      expect(docx.mimeType, 'application/octet-stream');
      expect(docx.name, 'office.docx');
      expect(docx.fileName, endsWith('.bin'));
      expect(await store.read(docx), [80, 75, 3, 4, 20]);
      expect((await imported('binary.txt', [0, 1, 2])).isGenericFile, isTrue);
      expect(
        (await imported('encoding.txt', [255, 254])).isGenericFile,
        isTrue,
      );
      final plain = await imported('no-extension', [97]);
      expect(plain.isText, isTrue);
      expect(utf8.decode(await store.read(plain)), 'a');
      await expectLater(
        imported('empty.txt', <int>[]),
        throwsA(isA<AttachmentException>()),
      );
      final large = File('${root.path}/large.pdf');
      final handle = await large.open(mode: FileMode.write);
      await handle.truncate(AttachmentStore.maxFileBytes + 1);
      await handle.close();
      final owned = await store.directory;
      final before = await owned.list().length;
      await expectLater(
        store.importFile(large.path, 'large.pdf'),
        throwsA(isA<AttachmentException>()),
      );
      expect(await owned.list().length, before);
    },
  );

  test(
    'image identity uses bytes and image-only selection rejects PDFs',
    () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      final image = await imported('misleading.txt', png);
      expect(image.mimeType, 'image/png');
      final pdf = await imported(
        'document.pdf',
        ascii.encode('%PDF-1.4\n%%EOF'),
      );
      await expectLater(
        store.importFile(
          (await store.file(pdf)).path,
          'document.pdf',
          imageOnly: true,
        ),
        throwsA(isA<AttachmentException>()),
      );
      await (await store.file(image)).delete();
      await expectLater(store.read(image), throwsA(isA<AttachmentException>()));
    },
  );

  test('cleanup retains referenced files and refuses path traversal', () async {
    final retained = await imported('retained.txt', utf8.encode('keep'));
    final orphan = await imported('orphan.txt', utf8.encode('remove'));
    final before = DateTime.now().add(const Duration(seconds: 1));
    await store.removeOrphans({retained.fileName}, before);
    expect(await (await store.file(retained)).exists(), isTrue);
    expect(await (await store.file(orphan)).exists(), isFalse);
    final malicious = ChatAttachment(
      name: 'bad',
      fileName: '../retained.txt',
      mimeType: 'text/plain',
      size: 4,
      estimatedTokens: 1,
    );
    await expectLater(
      store.file(malicious),
      throwsA(isA<AttachmentException>()),
    );
    expect(
      () => AttachmentStore.validateSelection(List.filled(10, retained)),
      throwsA(isA<AttachmentException>()),
    );
    await (await store.file(retained))
        .setLastModified(before.add(const Duration(days: 1)));
    await store.clear();
    expect(await (await store.directory).exists(), isFalse);
    expect(await File('${root.path}/retained.txt').exists(), isTrue);
  });

  test('DeepSeek file parts are flat and other hosts stay nested', () {
    expect(chatFileUsesFlatPart('https://api.deepseek.com'), isTrue);
    expect(chatFileUsesFlatPart('https://api.deepseek.com/v1'), isTrue);
    expect(chatFileUsesFlatPart('https://api.openai.com/v1'), isFalse);
    final flat = chatFileContent(
      filename: 'notes.docx',
      mimeType: 'application/octet-stream',
      base64Data: 'YQ==',
      flat: true,
    );
    expect(flat.containsKey('file'), isFalse);
    expect(flat['filename'], 'notes.docx');
    expect(flat['file_data'], 'data:application/octet-stream;base64,YQ==');
    final nested = chatFileContent(
      filename: 'report.pdf',
      mimeType: 'application/pdf',
      base64Data: 'YQ==',
      flat: false,
    );
    expect(
      (nested['file'] as Map)['file_data'],
      'data:application/pdf;base64,YQ==',
    );
  });

  test('one file may reach 30 MB and a message stays within 90 MB', () {
    ChatAttachment sized(int size) => ChatAttachment(
      name: 'report.pdf',
      fileName: '',
      mimeType: 'application/pdf',
      size: size,
      estimatedTokens: 1,
    );
    expect(
      () => AttachmentStore.validateSelection([
        sized(AttachmentStore.maxFileBytes),
      ]),
      returnsNormally,
    );
    expect(
      () => AttachmentStore.validateSelection(
        List.filled(3, sized(AttachmentStore.maxFileBytes)),
      ),
      returnsNormally,
    );
    expect(
      () => AttachmentStore.validateSelection(
        List.filled(4, sized(AttachmentStore.maxFileBytes)),
      ),
      throwsA(isA<AttachmentException>()),
    );
    final nine = [
      for (var i = 0; i < 9; i++) sized(AttachmentStore.maxTotalBytes ~/ 9),
    ];
    expect(() => AttachmentStore.validateSelection(nine), returnsNormally);
    expect(
      () => AttachmentStore.validateSelection([...nine, nine.first]),
      throwsA(isA<AttachmentException>()),
    );
    expect(
      () => AttachmentStore.validateSelection([
        sized(AttachmentStore.maxFileBytes + 1),
      ]),
      throwsA(isA<AttachmentException>()),
    );
  });

  for (final protocol in ApiProtocol.values) {
    test(
      '$protocol retains image, PDF and text in follow-ups and usage retry',
      () async {
        final image = await imported('photo.png', [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          0,
        ]);
        final pdf = await imported(
          'report.pdf',
          ascii.encode('%PDF-1.4\n%%EOF'),
        );
        final text = await imported(
          'data.csv',
          utf8.encode('name,value\nA,12'),
        );
        final binary = await imported('notes.docx', [80, 75, 3, 4]);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requests = <Map<String, dynamic>>[];
        server.listen((request) async {
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          if (protocol == ApiProtocol.openAi && requests.length == 1) {
            request.response.statusCode = 400;
            request.response.write(
              '{"error":{"message":"unsupported stream_options"}}',
            );
          } else if (protocol == ApiProtocol.anthropic) {
            request.response.write(
              'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\n\ndata: {"type":"message_stop"}\n\n',
            );
          } else {
            request.response.write(
              'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n',
            );
          }
          await request.response.close();
        });
        ChatMessage message(
          String role,
          String content, [
          List<ChatAttachment> attachments = const [],
        ]) => ChatMessage(
          id: 0,
          topicId: 1,
          role: role,
          content: content,
          createdAt: 0,
          attachments: attachments,
        );
        final history = [
          message('user', '', [image, pdf, text, binary]),
          message('assistant', 'seen'),
          message('user', 'Follow up'),
        ];
        expect(
          await ModelApiClient(
            ProviderConfig(
              id: 1,
              name: 'local',
              baseUrl: 'http://127.0.0.1:${server.port}/v1',
              model: 'unknown-model',
              protocol: protocol,
            ),
            'local-test-key',
            attachmentStore: store,
          ).streamReply(history, 'unknown-model', onUsage: (_) {}).join(),
          'ok',
        );
        final messages = requests.last['messages'] as List;
        expect(messages, hasLength(3));
        final parts = messages.first['content'] as List;
        expect(parts, hasLength(4));
        if (protocol == ApiProtocol.openAi) {
          expect(parts[0]['type'], 'image_url');
          expect(
            parts[0]['image_url']['url'],
            startsWith('data:image/png;base64,'),
          );
          expect(parts[1]['file']['filename'], 'report.pdf');
          expect(
            parts[1]['file']['file_data'],
            startsWith('data:application/pdf;base64,'),
          );
          expect(parts[3]['file']['filename'], 'notes.docx');
          expect(
            parts[3]['file']['file_data'],
            startsWith('data:application/octet-stream;base64,'),
          );
          expect(requests, hasLength(2));
          expect(requests[0]['messages'], requests[1]['messages']);
          expect(requests[1].containsKey('stream_options'), isFalse);
        } else {
          expect(parts[0]['type'], 'image');
          expect(parts[0]['source']['media_type'], 'image/png');
          expect(parts[1]['type'], 'document');
          expect(parts[1]['source']['media_type'], 'application/pdf');
          expect(parts[3]['type'], 'document');
          expect(parts[3]['source']['media_type'], 'application/octet-stream');
        }
        expect(parts[2]['text'], contains('name,value\nA,12'));
        expect(messages.last, {'role': 'user', 'content': 'Follow up'});
        expect(await (await store.file(image)).exists(), isTrue);
      },
    );
  }

  test('attachment capability errors are distinct from authentication and never retried', () async {
    final image = await imported('photo.png', [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var count = 0;
    var status = 400;
    server.listen((request) async {
      await request.drain<void>();
      count++;
      request.response.statusCode = status;
      request.response.write(
        '{"error":{"message":"model does not support image inputs local-test-key"}}',
      );
      await request.response.close();
    });
    Future<void> send(ApiErrorKind expected) async {
      await expectLater(
        ModelApiClient(
          ProviderConfig(
            id: 1,
            name: 'local',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'unknown',
            protocol: ApiProtocol.openAi,
          ),
          'local-test-key',
          attachmentStore: store,
        ).streamReply([
          ChatMessage(
            id: 1,
            topicId: 1,
            role: 'user',
            content: '',
            createdAt: 0,
            attachments: [image],
          ),
        ], 'unknown').join(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', expected)
              .having(
                (e) => e.toString(),
                'redacted',
                isNot(contains('local-test-key')),
              ),
        ),
      );
    }

    await send(ApiErrorKind.model);
    expect(count, 1);
    status = 401;
    await send(ApiErrorKind.auth);
    expect(count, 2);
  });

  test(
    'a schema rejection of the file block is a model capability error',
    () async {
      final file = await imported('notes.bin', [0, 1, 2, 3, 4]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 400;
        request.response.write(
          '{"error":{"message":"unknown field `file`, expected `file_data`"}}',
        );
        await request.response.close();
      });
      await expectLater(
        ModelApiClient(
          ProviderConfig(
            id: 1,
            name: 'local',
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            model: 'deepseek-flash',
            protocol: ApiProtocol.openAi,
          ),
          'local-test-key',
          attachmentStore: store,
        ).streamReply([
          ChatMessage(
            id: 1,
            topicId: 1,
            role: 'user',
            content: '看一下',
            createdAt: 0,
            attachments: [file],
          ),
        ], 'deepseek-flash').join(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.model,
          ),
        ),
      );
    },
  );

  test('context trims attachment turns before reading files; missing current files fail before HTTP', () async {
    final missing = ChatAttachment(
      name: 'missing.pdf',
      fileName: '00000000-0000-0000-0000-000000000000.pdf',
      mimeType: 'application/pdf',
      size: 10,
      estimatedTokens: 5000,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var count = 0;
    server.listen((request) async {
      final requestBody = jsonDecode(await utf8.decoder.bind(request).join());
      expect(requestBody['messages'], [
        {'role': 'user', 'content': 'latest'},
      ]);
      count++;
      request.response.write(
        'data: {"choices":[{"delta":{"content":"ok"}}]}\n\ndata: [DONE]\n\n',
      );
      await request.response.close();
    });
    ModelApiClient client() => ModelApiClient(
      ProviderConfig(
        id: 1,
        name: 'local',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'unknown',
        protocol: ApiProtocol.openAi,
      ),
      'local-key',
      attachmentStore: store,
    );
    final old = ChatMessage(
      id: 1,
      topicId: 1,
      role: 'user',
      content: '',
      createdAt: 0,
      attachments: [missing],
    );
    var omitted = 0;
    expect(
      await client()
          .streamReply(
            [
              old,
              const ChatMessage(
                id: 2,
                topicId: 1,
                role: 'assistant',
                content: 'old',
                createdAt: 0,
              ),
              const ChatMessage(
                id: 3,
                topicId: 1,
                role: 'user',
                content: 'latest',
                createdAt: 0,
              ),
            ],
            'unknown',
            contextWindowTokens: 8192,
            onContextTrimmed: (value) => omitted = value,
          )
          .join(),
      'ok',
    );
    expect(omitted, 2);
    expect(count, 1);
    await expectLater(
      client().streamReply([old], 'unknown').join(),
      throwsA(isA<ApiException>()),
    );
    expect(count, 1);
  });
}
