import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;
  test('v5 databases add nullable attachment metadata without rewriting old messages', () async {
    final statements = <String>[];
    final inserts = <Map<String, Object?>>[];
    var failTopicUpdate = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.tekartik.sqflite');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getDatabasesPath') {
        return '/attachment-migration-test';
      }
      if (call.method == 'openDatabase') return 1;
      final args = Map<String, Object?>.from(call.arguments as Map);
      final sql = args['sql'] as String? ?? '';
      if (call.method == 'query') {
        if (sql.contains('user_version')) {
          return [
            {'user_version': 5},
          ];
        }
        return <Map<String, Object?>>[];
      }
      if (call.method == 'execute') {
        statements.add(sql);
        if (sql.startsWith('BEGIN')) return {'transactionId': 1};
        return null;
      }
      if (call.method == 'insert') {
        inserts.add(args);
        return 7;
      }
      if (call.method == 'update') {
        if (failTopicUpdate) throw PlatformException(code: 'disk-error');
        return 1;
      }
      throw StateError('Unexpected ${call.method}');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = ChatStore.instance;
    await store.db;
    expect(
      statements.where((s) => s.startsWith('ALTER TABLE')),
      contains('ALTER TABLE messages ADD COLUMN attachments TEXT'),
    );
    expect(
      statements,
      contains('ALTER TABLE messages ADD COLUMN knowledge_sources TEXT'),
    );
    expect(
      statements.any((s) => s.startsWith('DELETE') || s.startsWith('DROP')),
      isFalse,
    );
    final old = ChatMessage.fromMap({
      'id': 1,
      'topic_id': 1,
      'role': 'user',
      'content': 'old message',
      'created_at': 1,
    });
    expect(old.content, 'old message');
    expect(old.attachments, isEmpty);
    const attachment = ChatAttachment(
      name: 'notes.txt',
      fileName: '00000000-0000-0000-0000-000000000000.txt',
      mimeType: 'text/plain',
      size: 4,
      estimatedTokens: 3,
    );
    await store.createTopicWithMessage(
      const ProviderConfig(
        id: 1,
        name: 'test',
        baseUrl: 'https://example.com/v1',
        model: 'm',
        protocol: ApiProtocol.openAi,
      ),
      'm',
      '',
      attachments: [attachment],
    );
    final messageInsert = inserts.firstWhere(
      (a) => (a['sql'] as String).contains('INTO messages'),
    );
    expect(
      messageInsert['arguments'] as List,
      contains(ChatAttachment.encode([attachment])),
    );
    expect(messageInsert['arguments'] as List, contains(''));
    expect(
      jsonDecode(ChatAttachment.encode([attachment])!).single['fileName'],
      attachment.fileName,
    );
    await store.addMessage(7, 'user', '', attachments: [attachment]);
    expect(statements.last, 'COMMIT');
    failTopicUpdate = true;
    await expectLater(
      store.addMessage(7, 'user', '', attachments: [attachment]),
      throwsA(isA<PlatformException>()),
    );
    expect(statements.last, 'ROLLBACK');
  });
}
