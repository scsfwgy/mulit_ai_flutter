import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  test(
    'memory profile stays local and does not enter the watch prompt',
    () async {
      final values = <String, String>{};
      var topicExists = true;
      const channel = MethodChannel('com.tekartik.sqflite');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getDatabasesPath') return '/test';
        if (call.method == 'openDatabase') return 1;
        final args = Map<String, Object?>.from(call.arguments as Map? ?? {});
        final sql = args['sql'] as String? ?? '';
        final params = (args['arguments'] as List?) ?? const [];
        if (call.method == 'execute') {
          if (sql.startsWith('BEGIN')) return {'transactionId': 1};
          return null;
        }
        if (call.method == 'query') {
          if (sql == 'PRAGMA user_version') {
            return [
              {'user_version': 7},
            ];
          }
          if (sql.contains('model_prompts') || sql.contains('FROM messages')) {
            return <Map<String, Object?>>[];
          }
          if (sql.contains('FROM topics')) {
            return topicExists
                ? [
                    {'id': 7},
                  ]
                : <Map<String, Object?>>[];
          }
          if (params.isEmpty) return <Map<String, Object?>>[];
          final key = params.first as String;
          return values.containsKey(key)
              ? [
                  {'value': values[key]},
                ]
              : <Map<String, Object?>>[];
        }
        if (call.method == 'insert') {
          values[params[0] as String] = params[1] as String;
          return 1;
        }
        if (call.method == 'update' && sql.contains('DELETE FROM settings')) {
          values.remove(params.single as String);
          return 1;
        }
        if (call.method == 'update') {
          if (sql.contains('DELETE FROM topics')) topicExists = false;
          return 1;
        }
        throw StateError('Unexpected database operation: ${call.method} $sql');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final store = ChatStore.instance;
      expect(await store.memoryEnabled(), isFalse);
      expect(await store.chatSystemPrompt(1, 'demo'), isEmpty);
      expect(await store.systemPrompt(1, 'demo'), isEmpty);

      await store.setMemoryEnabled(true);
      await store.saveMemoryProfile('字' * (memoryProfileMaxChars + 1));
      expect((await store.memoryProfile()).runes.length, memoryProfileMaxChars);
      expect(await store.memoryRevision(), 1);
      final saved = await store.memoryProfile();
      expect(await store.chatSystemPrompt(1, 'demo'), memoryPromptBlock(saved));
      await store.setMemoryInGlobalPrompt(true);
      expect(await store.chatSystemPrompt(1, 'demo'), memoryPromptBlock(saved));
      await store.setMemoryTopicOverride(7, false);
      expect(await store.chatSystemPrompt(1, 'demo', topicId: 7), isEmpty);
      await store.setMemoryInGlobalPrompt(false);
      expect(await store.chatSystemPrompt(1, 'demo'), isEmpty);
      await store.deleteSetting(memoryTopicSetting(7));
      expect(await store.chatSystemPrompt(1, 'demo', topicId: 7), isEmpty);
      expect(await store.chatUsesMemory(7), isFalse);
      expect(
        await store.advanceMemoryCursor(
          revision: 1,
          topicId: 7,
          cursorMessageId: 4,
        ),
        isFalse,
      );
      expect(
        await store.saveMergedMemory(
          revision: 1,
          profile: 'blocked',
          topicId: 7,
          cursorMessageId: 4,
        ),
        isFalse,
      );
      expect(await store.memoryProfile(), saved);
      await store.setMemoryTopicOverride(7, true);
      expect(
        await store.chatSystemPrompt(1, 'demo', topicId: 7),
        memoryPromptBlock(saved),
      );
      expect(
        await store.chatSystemPrompt(1, 'demo', topicOverride: true),
        memoryPromptBlock(saved),
      );
      expect(await store.systemPrompt(1, 'demo'), isEmpty);

      expect(
        await store.saveMergedMemory(
          revision: 0,
          profile: '被手改覆盖前的结果',
          topicId: 7,
          cursorMessageId: 4,
        ),
        isFalse,
      );
      expect(await store.memoryProfile(), saved);
      expect(await store.memoryCursor(7), 0);

      expect(
        await store.saveMergedMemory(
          revision: 1,
          profile: '喜欢喝茶',
          topicId: 7,
          cursorMessageId: 4,
        ),
        isTrue,
      );
      expect(await store.memoryProfile(), '喜欢喝茶');
      expect(await store.memoryCursor(7), 4);

      // In-flight results must still respect the master and per-chat switches.
      for (final scope in ['master', 'topic']) {
        await store.setMemoryEnabled(scope != 'master');
        await store.setMemoryInGlobalPrompt(false);
        await store.setMemoryTopicOverride(7, scope != 'topic');
        expect(
          await store.saveMergedMemory(
            revision: 1,
            profile: '失效结果',
            topicId: 7,
            cursorMessageId: 9,
          ),
          isFalse,
        );
        expect(
          await store.advanceMemoryCursor(
            revision: 1,
            topicId: 7,
            cursorMessageId: 9,
          ),
          isFalse,
        );
        expect(await store.memoryProfile(), '喜欢喝茶');
        expect(await store.memoryCursor(7), 4);
      }
      await store.setMemoryEnabled(true);
      await store.setMemoryTopicOverride(7, true);

      await store.saveMemoryProfile('手改');
      expect(await store.memoryRevision(), 2);
      expect(
        await store.advanceMemoryCursor(
          revision: 1,
          topicId: 7,
          cursorMessageId: 9,
        ),
        isFalse,
      );
      expect(await store.memoryCursor(7), 4);
      expect(await store.memoryProfile(), '手改');

      await store.deleteTopic(7);
      expect(await store.memoryCursor(7), 0);
      expect(await store.memoryTopicOverride(7), isNull);
      await store.setMemoryInGlobalPrompt(true);
      expect(
        await store.saveMergedMemory(
          revision: 2,
          profile: '已删除话题的结果',
          topicId: 7,
          cursorMessageId: 99,
        ),
        isFalse,
      );
      expect(await store.memoryCursor(7), 0);
      expect(await store.memoryProfile(), '手改');
    },
  );
}
