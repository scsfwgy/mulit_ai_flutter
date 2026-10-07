import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/provider/provider_screen.dart';
import 'package:mulit_ai_flutter/search/search_service.dart';
import 'package:mulit_ai_flutter/search/search_settings_screen.dart';
import 'package:mulit_ai_flutter/settings/privacy_screen.dart';
import 'package:mulit_ai_flutter/settings/settings_screen.dart';
import 'package:mulit_ai_flutter/voice/voice_settings_screen.dart';
import 'package:mulit_ai_flutter/watch/watch_settings_screen.dart';

import 'sqflite_stub.dart';

/// 界面不得直接渲染未翻译的 `i18n.*` key。
///
/// 迁移后大量「数据载体」保存的是 key 而不是译文：枚举字段（`AppSkin.label`、
/// `SearchService.label`、`ApiProtocol.label`）、Map 值（`billingLabel`）、
/// 默认参数（`ApiKeyHelpRow.title`）、switch 分支与常量。
///
/// `IosRow` / `IosSection` / `iosAppBar` 会在内部对 title/subtitle/footer 调用
/// `T`，因此经它们传入的 key 是安全的。**不受保护的渲染点**才是风险所在：
/// `Text`、`SelectableText`、`CupertinoTextField.placeholder`，以及
/// `TextEditingController` 的初始文本（`TextEditingController(text: key)`
/// 不会经过任何翻译）。这类缺陷已实际发生，故显式守卫。
///
/// 覆盖范围：无数据库依赖即可渲染的页面；需要 sqflite 数据的列表页
/// （搜索/语音/手表服务列表里的已保存条目）仍靠各自的功能测试与人工核查。
void _expectNoKeyLeak(WidgetTester tester, String screen) {
  var rendered = 0;
  final leaked = <String>[];

  for (final element in find.byType(Text).evaluate()) {
    rendered++;
    final data = (element.widget as Text).data;
    if (data != null && data.contains('i18n.')) leaked.add(data);
  }
  for (final element in find.byType(SelectableText).evaluate()) {
    rendered++;
    final data = (element.widget as SelectableText).data;
    if (data != null && data.contains('i18n.')) leaked.add(data);
  }
  for (final element in find.byType(EditableText).evaluate()) {
    rendered++;
    final text = (element.widget as EditableText).controller.text;
    if (text.contains('i18n.')) leaked.add('输入框内容：$text');
  }
  for (final element in find.byType(CupertinoTextField).evaluate()) {
    final placeholder = (element.widget as CupertinoTextField).placeholder;
    if (placeholder != null && placeholder.contains('i18n.')) {
      leaked.add('输入框占位：$placeholder');
    }
  }

  // 守卫断言本身：页面必须真的渲染出内容，否则空结果会假通过。
  expect(rendered, greaterThan(0), reason: '$screen 没有渲染任何内容');
  expect(
    leaked,
    isEmpty,
    reason: '$screen 直接渲染了未翻译的 key：\n${leaked.join('\n')}',
  );
}

void main() {
  setUpAll(useSqflitePluginFactory);

  const savedSearch = SearchProviderConfig(
    id: 'saved',
    name: 'Tavily',
    service: SearchService.tavily,
    endpoint: 'https://api.tavily.com/search',
  );

  final screens = <String, Widget Function()>{
    '搜索服务编辑器（新建）': SearchServiceEditor.new,
    '搜索服务编辑器（已保存）': () => const SearchServiceEditor(service: savedSearch),
    '外观设置': AppearanceScreen.new,
    '消息设置': MessageSettingsScreen.new,
    '关于': AboutScreen.new,
    '隐私与数据': PrivacyScreen.new,
    '服务列表': ProviderScreen.new,
    '服务编辑器': ProviderEditor.new,
    '搜索设置': SearchSettingsScreen.new,
    '语音设置': VoiceSettingsScreen.new,
    '手表设置': WatchSettingsScreen.new,
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key}不直接渲染未翻译的 key', (tester) async {
      installEmptyDatabaseStub();
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(home: entry.value()));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      _expectNoKeyLeak(tester, entry.key);
    });
  }
}
