import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/chat/chat_draft_store.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/chat_draft.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/app_preferences.dart';
import 'package:mulit_ai_flutter/core/project_store.dart';
import 'package:mulit_ai_flutter/core/sqlite_desktop.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database db;
  late ChatDraftStore drafts;
  final store = ChatStore.instance;
  const provider = ProviderConfig(
    id: 1,
    name: 'Fixture',
    baseUrl: 'https://example.com/v1',
    model: 'test',
    protocol: ApiProtocol.openAi,
  );
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('ai-link-drafts-');
    databaseFactory = await createDesktopDatabaseFactory(root);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    db = await store.db;
  });
  setUp(() async {
    await db.delete('topics');
    await db.delete('projects');
    await db.delete('settings');
    await db.insert('providers', {
      'id': 1,
      ...provider.toMap(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    drafts = ChatDraftStore();
    await drafts.refreshEpoch();
  });
  tearDownAll(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<int> topic() =>
      store.createTopicWithMessage(provider, 'test', 'Original message');
  Future<ChatAttachment> file(String text) async {
    final source = await File('${root.path}/source.txt').writeAsString(text);
    return AttachmentStore.instance.importFile(source.path, '材料.txt');
  }

  test(
    'drafts isolate chats and projects and restore after a new store instance',
    () async {
      final a = await topic(), b = await topic();
      final project = await store.saveProject(name: 'Project');
      final attachment = await file('Private attachment');
      await drafts.save(
        chatDraftKey(topicId: a),
        ChatDraft(text: 'Draft A', attachments: [attachment]),
      );
      await drafts.save(
        chatDraftKey(topicId: b),
        const ChatDraft(text: 'Draft B'),
      );
      await drafts.save(
        chatDraftKey(projectId: project),
        const ChatDraft(text: 'Project draft'),
      );
      await drafts.save(
        chatDraftKey(),
        const ChatDraft(text: 'Ungrouped draft'),
      );
      final reopened = ChatDraftStore();
      await reopened.refreshEpoch();
      expect((await reopened.read(chatDraftKey(topicId: a))).text, 'Draft A');
      expect(
        (await reopened.read(chatDraftKey(topicId: a)))
            .attachments
            .single
            .fileName,
        attachment.fileName,
      );
      expect((await reopened.read(chatDraftKey(topicId: b))).text, 'Draft B');
      expect(
        (await reopened.read(chatDraftKey(projectId: project))).text,
        'Project draft',
      );
      expect((await reopened.read(chatDraftKey())).text, 'Ungrouped draft');
      expect(await store.topics(), hasLength(2));
    },
  );
  test(
    'queued saves finish in order, and reassignment moves the checkpoint',
    () async {
      final a = await topic();
      final project = await store.saveProject(name: 'Target');
      final key = chatDraftKey(topicId: a),
          target = chatDraftKey(projectId: project);
      final first = drafts.save(key, const ChatDraft(text: 'old'));
      final last = drafts.save(key, const ChatDraft(text: 'new'));
      await Future.wait([first, last]);
      expect((await drafts.read(key)).text, 'new');
      await drafts.save(target, await drafts.read(key), moveFrom: key);
      expect((await drafts.read(key)).isEmpty, true);
      expect((await drafts.read(target)).text, 'new');
      expect(drafts.isBusy, false);
    },
  );
  test('successful send consumes its draft atomically and retains message attachments', () async {
    final a = await topic();
    final attachment = await file('Sent data');
    final key = chatDraftKey(topicId: a);
    await drafts.save(
      key,
      ChatDraft(text: 'To send', attachments: [attachment]),
    );
    await store.addMessage(
      a,
      'user',
      'To send',
      attachments: [attachment],
      draftKey: key,
    );
    expect((await drafts.read(key)).isEmpty, true);
    await store.removeOrphanAttachments(
      DateTime.now().add(const Duration(seconds: 1)),
    );
    expect(
      await (await AttachmentStore.instance.file(attachment)).exists(),
      true,
    );
    await drafts.save(chatDraftKey(), const ChatDraft(text: 'First message'));
    await store.createTopicWithMessage(
      provider,
      'test',
      'First message',
      draftKey: chatDraftKey(),
    );
    expect((await drafts.read(chatDraftKey())).isEmpty, true);
  });
  test(
    'failed send rolls back the message, new topic and draft consumption',
    () async {
      const key = 'chat_draft:new:0';
      await drafts.save(key, const ChatDraft(text: 'fail'));
      await db.execute(
        "CREATE TRIGGER fail_draft_message BEFORE INSERT ON messages WHEN NEW.content = 'fail' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      try {
        await expectLater(
          store.createTopicWithMessage(provider, 'test', 'fail', draftKey: key),
          throwsA(isA<DatabaseException>()),
        );
        expect(await store.topics(), isEmpty);
        expect((await drafts.read(key)).text, 'fail');
      } finally {
        await db.execute('DROP TRIGGER fail_draft_message');
      }
    },
  );
  test(
    'orphan cleanup keeps draft files and removes unreferenced copies',
    () async {
      final kept = await file('Keep draft'),
          orphan = await file('Remove orphan');
      await drafts.save(chatDraftKey(), ChatDraft(attachments: [kept]));
      await store.removeOrphanAttachments(
        DateTime.now().add(const Duration(seconds: 1)),
      );
      expect(await (await AttachmentStore.instance.file(kept)).exists(), true);
      expect(
        await (await AttachmentStore.instance.file(orphan)).exists(),
        false,
      );
    },
  );
  test('deleting chats and projects removes their drafts and files', () async {
    final a = await topic();
    final attachment = await file('Delete draft');
    final snapshot = ChatDraft(text: 'Gone', attachments: [attachment]);
    await drafts.save(chatDraftKey(topicId: a), snapshot);
    await store.deleteTopic(a);
    expect((await drafts.read(chatDraftKey(topicId: a))).isEmpty, true);
    expect(
      await (await AttachmentStore.instance.file(attachment)).exists(),
      false,
    );
    await drafts.save(chatDraftKey(topicId: a), snapshot);
    expect((await drafts.read(chatDraftKey(topicId: a))).isEmpty, true);
    final project = await store.saveProject(name: 'Delete project');
    final projectFile = await file('Project draft');
    await drafts.save(
      chatDraftKey(projectId: project),
      ChatDraft(attachments: [projectFile]),
    );
    await store.deleteProject(project);
    expect((await drafts.read(chatDraftKey(projectId: project))).isEmpty, true);
    expect(
      await (await AttachmentStore.instance.file(projectFile)).exists(),
      false,
    );
  });
  test(
    'late writes cannot resurrect drafts after clearing local data',
    () async {
      await drafts.save(
        chatDraftKey(),
        const ChatDraft(text: 'Old private text'),
      );
      await store.clearAllData();
      await drafts.save(
        chatDraftKey(),
        const ChatDraft(text: 'Late old write'),
      );
      expect(await store.setting(chatDraftKey()), isNull);
      expect(await drafts.refreshEpoch(), true);
      expect((await drafts.read(chatDraftKey())).isEmpty, true);
      await drafts.save(chatDraftKey(), const ChatDraft(text: 'Fresh draft'));
      expect((await drafts.read(chatDraftKey())).text, 'Fresh draft');
    },
  );
  test(
    'compact customization survives reloads without changing standard mode',
    () async {
      final prefs = AppPreferences.instance;
      await prefs.load();
      expect(prefs.simpleMessageInfo, false);
      await prefs.setChatInfoVisible(ChatInfoField.tokens, true);
      await prefs.setSimpleMessageInfo(true);
      expect(prefs.showChatInfo(ChatInfoField.tokens), false);
      expect(prefs.showChatInfo(ChatInfoField.copy), true);
      expect(prefs.showChatInfo(ChatInfoField.speech), true);
      await prefs.setChatInfoVisible(ChatInfoField.tokens, true);
      await prefs.setChatInfoVisible(ChatInfoField.modelId, true);
      await prefs.setChatInfoVisible(ChatInfoField.copy, false);
      await prefs.load();
      expect(prefs.simpleMessageInfo, true);
      expect(prefs.showChatInfo(ChatInfoField.tokens), true);
      expect(prefs.showChatInfo(ChatInfoField.modelId), true);
      expect(prefs.showChatInfo(ChatInfoField.copy), false);
      await prefs.setSimpleMessageInfo(false);
      expect(prefs.showChatInfo(ChatInfoField.tokens), true);
      expect(prefs.showChatInfo(ChatInfoField.copy), true);
      await prefs.setSimpleMessageInfo(true);
      expect(prefs.showChatInfo(ChatInfoField.copy), false);
      prefs.simpleMessageInfo = false;
    },
  );
}
