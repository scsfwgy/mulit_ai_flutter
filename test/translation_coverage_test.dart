import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/app_preferences.dart';
import 'package:mulit_ai_flutter/chat_context.dart';

/// Parse Dart rather than matching source text: comments, adjacent strings,
/// switch/conditional choices and indirectly translated iOS labels are covered.
class _UiStrings extends RecursiveAstVisitor<void> {
  final values = <String, int>{};

  bool _isUiExpression(AstNode node) {
    for (
      AstNode? parent = node.parent;
      parent != null;
      parent = parent.parent
    ) {
      if (parent is FunctionBody || parent is StringInterpolation) return false;
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
        if (call is MethodInvocation && call.methodName.name == 'tr') {
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
            }.contains(call.constructorName.type.toSource())) {
          return true;
        }
      }
    }
    return false;
  }

  void _record(StringLiteral node) {
    if (node.parent is AdjacentStrings) return;
    final value = node.stringValue;
    if (value != null &&
        RegExp(r'[\u4e00-\u9fff]').hasMatch(value) &&
        _isUiExpression(node)) {
      values[value] = node.offset;
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _record(node);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _record(node);
    super.visitAdjacentStrings(node);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all static Chinese UI labels and errors have English translations', () {
    final preferences = AppPreferences.instance;
    final previous = preferences.language;
    preferences.language = AppLanguage.en;
    addTearDown(() => preferences.language = previous);
    final missing = <String>[];
    var checked = 0;
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('app_preferences.dart')) {
        continue;
      }
      final parsed = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      );
      final visitor = _UiStrings();
      parsed.unit.accept(visitor);
      for (final entry in visitor.values.entries) {
        checked++;
        if (tr(entry.key) == entry.key) {
          missing.add(
            '${file.path}:${parsed.lineInfo.getLocation(entry.value).lineNumber}: ${entry.key}',
          );
        }
      }
    }
    // Labels carried by enums/constants are translated later through variables.
    for (final label in [
      ...AppSkin.values.map((value) => value.label),
      ...ChatInfoField.values.map((value) => value.label),
      ChatContext.limitMessage,
      ChatContext.serverLimitMessage,
    ]) {
      if (tr(label) == label) missing.add(label);
    }
    expect(checked, greaterThan(250));
    expect(
      missing,
      isEmpty,
      reason: 'Missing English translations:\n${missing.join('\n')}',
    );
  });

  test('coverage scanner sees indirect, multiline and conditional labels', () {
    final visitor = _UiStrings();
    parseString(
      content: '''
      void build() {
        tr('直接');
        IosRow(title: '间接');
        IosSection(footer: '多行' '合并');
        Text(tr(flag ? '选择一' : '选择二'));
        Text(tr(switch (mode) { 1 => '分支一', _ => '分支二' }));
        // tr('注释');
        final providerName = '服务名称';
      }
    ''',
    ).unit.accept(visitor);
    expect(visitor.values.keys.toSet(), {
      '直接',
      '间接',
      '多行合并',
      '选择一',
      '选择二',
      '分支一',
      '分支二',
    });
  });
}
