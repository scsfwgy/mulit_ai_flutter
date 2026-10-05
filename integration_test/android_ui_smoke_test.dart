import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mulit_ai_flutter/data.dart';
import 'package:mulit_ai_flutter/main.dart' as app;
import 'package:mulit_ai_flutter/provider_screen.dart';

/// Render phone regression screenshots without network requests or user-data reset.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android phone pages remain usable with desktop adaptations', (
    tester,
  ) async {
    final store = ChatStore.instance;
    final savedSelection = await store.setting('last_chat_selection');
    int? providerId;
    int? topicId;
    Future<void> screenshot(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    try {
      app.main();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await binding.convertFlutterSurfaceToImage();
      await screenshot('android-welcome');
      providerId = await store.saveProvider(
        ProviderConfig(
          id: 0,
          name: 'UI regression test',
          baseUrl: 'http://127.0.0.1:1/v1',
          model: 'local-ui-model',
          protocol: ApiProtocol.openAi,
        ),
      );
      final provider = (await store.providers()).firstWhere(
        (p) => p.id == providerId,
      );
      topicId = await store.createTopicWithMessage(
        provider,
        provider.model,
        'Android UI regression',
      );
      await store.addMessage(
        topicId,
        'assistant',
        '## Markdown 检查\n\n这是一段用于检查长文本换行的本地内容，不会向服务商发送请求。\n\n'
            '| 项目 | 状态 |\n| --- | --- |\n| 聊天 | 正常 |\n| 模型设置 | 正常 |',
        modelId: provider.model,
        provider: provider,
      );
      // Remount to read only the freshly created local fixture.
      await tester.pumpWidget(const SizedBox());
      app.main();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byIcon(CupertinoIcons.line_horizontal_3));
      await screenshot('android-topics');
      await tester.tap(find.text('Android UI regression'));
      await screenshot('android-chat');
      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.enterText(find.byType(CupertinoTextField).first, '键盘与输入框检查');
      await screenshot('android-keyboard');
      await tester.pumpWidget(const MaterialApp(home: ProviderScreen()));
      await screenshot('android-providers');
      await tester.pumpWidget(
        MaterialApp(home: ProviderEditor(config: provider)),
      );
      await screenshot('android-provider-editor');
    } finally {
      await tester.pumpWidget(const SizedBox());
      if (topicId != null) await store.deleteTopic(topicId);
      if (providerId != null) await store.deleteProvider(providerId);
      if (savedSelection == null) {
        await (await store.db).delete(
          'settings',
          where: 'key = ?',
          whereArgs: ['last_chat_selection'],
        );
      } else {
        await store.saveSetting('last_chat_selection', savedSelection);
      }
    }
  });
}
