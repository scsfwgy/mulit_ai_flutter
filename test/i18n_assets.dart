import 'dart:convert';
import 'dart:io';

import 'package:mulit_ai_flutter/i18n/app_language.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

/// 测试侧的语言配置读取工具。
///
/// 刻意走文件系统而不是 `rootBundle`：读取打包资源需要先初始化
/// `TestWidgetsFlutterBinding`，而该 binding 会把 `HttpOverrides.global`
/// 换成「所有请求返回 400」的桩，使依赖真实回环 `HttpServer` 的协议测试
/// （`core_test`、`search_service_test`、`chat_request_limits_test` 等）
/// 全部失败。直接读文件即可在不引入 binding 的前提下拿到同一份文案表。
///
/// `flutter test` 的工作目录是包根目录，因此相对路径可用。

/// 读取指定语言的配置原文。
String readLanguageAsset(String code) =>
    File('${I18n.assetPrefix}$code.json').readAsStringSync();

/// 解析一份语言配置为 `key -> 文案`。
Map<String, String> parseLanguageAsset(String text) =>
    (jsonDecode(text) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value.toString()),
    );

/// 载入 [I18n.languages] 中的全部语言表并注入 [I18n]。
///
/// 当前语言固定为简体中文，与测试断言的期望文案一致。
void seedI18nForTests() {
  I18n.seed({
    for (final language in I18n.languages)
      language: parseLanguageAsset(readLanguageAsset(language.code)),
  });
  I18n.apply(AppLanguage.zh);
}
