import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:mulit_ai_flutter/i18n/app_language.dart';

/// 本地化文案：每种语言一个独立配置 `assets/i18n/<code>.json`。
///
/// key 统一带 `i18n.` 前缀（见 `assets/i18n/zh.json`）。启动时调用 [I18n.load]
/// 把全部语言表载入内存，运行时切换只需 [I18n.apply]；[T]/[F] 同步查内存表，
/// 未命中依次回退到中文表，再回退到 key 本身，避免界面出现空串。
///
/// 新增语言：在 [AppLanguage] 登记后于 `assets/i18n/` 放入同名 JSON 即可，
/// 并把该语言加入 [I18n.languages] 预载列表（可选，未预载时按需读取）。
abstract final class I18n {
  static const String assetPrefix = 'assets/i18n/';

  /// 回退语言：任何缺失 key 都以简体中文兜底。
  static const AppLanguage fallback = AppLanguage.zh;

  /// 启动时预载的语言表。新增语言时在此追加。
  static const List<AppLanguage> languages = [
    AppLanguage.zh,
    AppLanguage.zhTW,
    AppLanguage.en,
  ];

  static final Map<AppLanguage, Map<String, String>> _tables = {};

  /// 用户选择的语言（可能是 [AppLanguage.system]）。
  static AppLanguage mode = AppLanguage.system;

  /// 资源是否已载入。
  static bool get loaded => _tables.isNotEmpty;

  /// 当前实际查表的语言。
  static AppLanguage get current => AppLanguage.resolve(mode);

  /// 载入全部语言表并应用 [language]。
  ///
  /// 幂等：语言表已常驻时只切换当前语言，不再重复读取资源。这样在
  /// `testWidgets` 的 FakeAsync 环境中重复调用不会因真实文件 I/O 而挂起。
  static Future<void> load(AppLanguage language) async {
    if (!loaded) {
      for (final item in languages) {
        _tables[item] = await _read(item.code);
      }
    }
    apply(language);
  }

  /// 同步切换当前语言（语言表已常驻内存）。
  static void apply(AppLanguage language) => mode = language;

  /// 查 [key] 的当前语言文案；未命中回退中文，再回退 key 本身。
  static String lookup(String key) {
    final text = _tables[current]?[key];
    if (text != null && text.isNotEmpty) return text;
    final backup = _tables[fallback]?[key];
    return (backup != null && backup.isNotEmpty) ? backup : key;
  }

  /// 查 [key] 在指定语言下的文案；未命中回退 key 本身。
  ///
  /// 用于把「历史上在某个语言下保存下来的译文」还原回同一个 key：旧版服务
  /// 配置里存的是当时的译文（例如中文的 `GLM 智谱`），而不是 key。
  static String lookupIn(AppLanguage language, String key) {
    final text = _tables[language]?[key];
    return (text != null && text.isNotEmpty) ? text : key;
  }

  static Future<Map<String, String>> _read(String code) async {
    final data = await rootBundle.loadString('$assetPrefix$code.json');
    final raw = Map<String, dynamic>.from(jsonDecode(data));
    return Map<String, String>.unmodifiable(
      raw.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  /// 仅用于测试：直接注入已解析的文案表，跳过资源读取。
  ///
  /// `test/flutter_test_config.dart` 用它预载文案。测试改为直接读
  /// `assets/i18n/*.json`，从而无需调用
  /// `TestWidgetsFlutterBinding.ensureInitialized()`——该 binding 会把
  /// `HttpOverrides.global` 换成「所有请求返回 400」的桩，使依赖真实回环
  /// `HttpServer` 的协议测试全部失败。
  static void seed(Map<AppLanguage, Map<String, String>> tables) {
    _tables
      ..clear()
      ..addAll(tables);
  }

  /// 仅用于测试：重置已载入的语言表。
  static void resetForTesting() {
    _tables.clear();
    mode = AppLanguage.system;
  }
}

/// 翻译 [key]。
///
/// 具备幂等性：传入的若不是已知 key（例如已经是本地化后的文本、用户数据或
/// 服务端返回内容），原样返回。因此上游已翻译的文本可以安全地再次经过 [T]。
String T(String key) => I18n.lookup(key);

/// 翻译 [key] 并替换 `{0}`、`{1}`… 占位符。
String F(String key, List<Object?> args) {
  var result = I18n.lookup(key);
  for (var i = 0; i < args.length; i++) {
    result = result.replaceAll('{$i}', '${args[i]}');
  }
  return result;
}
