import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/i18n/app_language.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

import 'i18n_assets.dart';

/// 解析 Dart AST 而非匹配源码文本：注释、相邻字符串、条件/switch 分支与
/// 经变量间接传入的标签都能覆盖。
///
/// 已知盲区（不视为回归）：字符串插值内部的字面量（如
/// `'${name ?? '默认值'}'`）无法用 AST 精确归属，需要人工检查。
class _UiStrings extends RecursiveAstVisitor<void> {
  final values = <String, int>{};

  /// 访问过的字符串字面量总数，用于确认扫描器确实跑到了代码。
  int scanned = 0;

  bool _isUiExpression(AstNode node) {
    for (
      AstNode? parent = node.parent;
      parent != null;
      parent = parent.parent
    ) {
      if (parent is FunctionBody || parent is StringInterpolation) return false;
      if (parent is DefaultFormalParameter) return true;
      if (parent is EnumConstantDeclaration) return true;
      if (parent is NamedExpression &&
          {
            'title',
            'subtitle',
            'footer',
            'label',
            'placeholder',
            'semanticLabel',
          }.contains(parent.name.label.name)) {
        return true;
      }
      if (parent is ArgumentList) {
        final call = parent.parent;
        if (call is MethodInvocation &&
            {
              'tr',
              'T',
              'F',
              'Text',
              'SelectableText',
            }.contains(call.methodName.name)) {
          return true;
        }
        if (call is InstanceCreationExpression &&
            {
              'Text',
              'SelectableText',
              'ApiException',
              'SearchException',
              'VoiceException',
              'FormatException',
              'WatchChatException',
              'StateError',
            }.contains(call.constructorName.type.toSource())) {
          return true;
        }
      }
    }
    return false;
  }

  void _record(AstNode node, String? value) {
    if (value == null || !RegExp(r'[\u4e00-\u9fff]').hasMatch(value)) return;
    if (value.startsWith('i18n.')) return;
    if (_isUiExpression(node)) values[value] = node.offset;
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    scanned++;
    if (node.parent is! AdjacentStrings) _record(node, node.stringValue);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    scanned++;
    _record(node, node.stringValue);
    super.visitAdjacentStrings(node);
  }
}

/// 收集 `T('i18n.x')` / `F('i18n.x'` 中引用的 key。
class _KeyUses extends RecursiveAstVisitor<void> {
  final keys = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'T' || node.methodName.name == 'F') {
      final args = node.argumentList.arguments;
      if (args.isNotEmpty && args.first is SimpleStringLiteral) {
        final value = (args.first as SimpleStringLiteral).stringValue;
        if (value != null && value.startsWith('i18n.')) keys.add(value);
      }
    }
    super.visitMethodInvocation(node);
  }
}

Map<String, String> _read(String code) =>
    parseLanguageAsset(readLanguageAsset(code));

List<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where((file) => !file.path.contains('/i18n/'))
    .where((file) => !file.path.endsWith('app_preferences.dart'))
    .toList();

void main() {
  late Map<String, String> zh;
  late Map<String, String> en;
  late Map<String, String> zhTw;

  setUpAll(() {
    zh = _read('zh');
    en = _read('en');
    zhTw = _read('zh-TW');
  });

  test('每份语言配置的 key 集合完全一致', () {
    expect(en.keys.toSet(), zh.keys.toSet());
    expect(zhTw.keys.toSet(), zh.keys.toSet());
    expect(zh, isNotEmpty);
  });

  test('所有语言配置都不含空值与重复 key', () {
    for (final code in ['zh', 'en', 'zh-TW']) {
      final text = readLanguageAsset(code);
      final raw = jsonDecode(text) as Map<String, dynamic>;
      final duplicates = <String>[];
      RegExp(r'^\s*"(i18n\.[^"]+)":', multiLine: true)
          .allMatches(text)
          .map((match) => match.group(1)!)
          .fold(<String, int>{}, (counts, key) {
            counts[key] = (counts[key] ?? 0) + 1;
            return counts;
          })
          .forEach((key, count) {
            if (count > 1) duplicates.add(key);
          });
      expect(duplicates, isEmpty, reason: '$code.json 存在重复 key');
      expect(
        raw.entries.where((entry) => entry.value.toString().trim().isEmpty),
        isEmpty,
        reason: '$code.json 存在空值',
      );
    }
  });

  test('源码引用的每个 key 在全部语言中都存在', () {
    final used = <String>{};
    for (final file in _dartFiles()) {
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      );
      final visitor = _KeyUses();
      parsed.unit.accept(visitor);
      used.addAll(visitor.keys);
    }
    expect(used.length, greaterThan(250));
    final missing = <String>[];
    for (final key in used.toSet()) {
      if (!zh.containsKey(key)) missing.add('$key (zh)');
      if (!en.containsKey(key)) missing.add('$key (en)');
      if (!zhTw.containsKey(key)) missing.add('$key (zh-TW)');
    }
    expect(missing, isEmpty, reason: '缺失的 key：\n${missing.join('\n')}');
  });

  test('界面中不再存在未本地化的中文字面量', () {
    final leftovers = <String>[];
    var scanned = 0;
    for (final file in _dartFiles()) {
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      );
      final visitor = _UiStrings();
      parsed.unit.accept(visitor);
      scanned += visitor.scanned;
      for (final entry in visitor.values.entries) {
        leftovers.add(
          '${file.path}:${parsed.lineInfo.getLocation(entry.value).lineNumber}: ${entry.key}',
        );
      }
    }
    // 守卫扫描器本身：迁移完成后界面文案会全部走 T/F，剩余字面量为 0，
    // 因此用"访问过的字符串字面量总数"确认扫描确实跑到了源码。
    expect(scanned, greaterThan(500));
    expect(
      leftovers,
      isEmpty,
      reason: '未走 T/F 的中文界面文案：\n${leftovers.join('\n')}',
    );
  });

  test('T/F 具备幂等性：非 key 文本原样返回', () {
    expect(T('claude-opus-4-6'), 'claude-opus-4-6');
    expect(T('AI Link'), 'AI Link');
    expect(F('i18n.request_failed', ['401', 'denied']), contains('401'));
  });

  test('语言枚举可从持久化值还原并解析跟随系统', () {
    expect(AppLanguage.fromCode('zh-TW'), AppLanguage.zhTW);
    expect(AppLanguage.fromCode('zhTW'), AppLanguage.zhTW);
    expect(AppLanguage.fromCode('en'), AppLanguage.en);
    expect(AppLanguage.fromCode('fr'), AppLanguage.system);
    expect(AppLanguage.fromCode(null), AppLanguage.system);
    expect(AppLanguage.resolve(AppLanguage.en), AppLanguage.en);
  });

  test('覆盖扫描能识别间接、多行与条件标签', () {
    final visitor = _UiStrings();
    parseString(
      content: '''
      void build() {
        T('i18n.direct');
        IosRow(title: '间接');
        IosSection(footer: '多行' '合并');
        Text(flag ? '选择一' : '选择二');
        Text(switch (mode) { 1 => '分支一', _ => '分支二' });
        // '注释';
        final providerName = '服务名称';
      }
    ''',
    ).unit.accept(visitor);
    expect(visitor.values.keys.toSet(), {
      '间接',
      '多行合并',
      '选择一',
      '选择二',
      '分支一',
      '分支二',
    });
  });
}
