import 'dart:ui' show PlatformDispatcher;

/// 应用语言枚举。新增语言只需在此登记并在 `assets/i18n/` 增加同名 JSON 配置。
///
/// [code] 同时用作资源文件名（`assets/i18n/<code>.json`）与持久化值。
enum AppLanguage {
  system('system'),
  zh('zh'),
  zhTW('zh-TW'),
  en('en');

  const AppLanguage(this.code);

  /// 资源文件名与持久化值。
  final String code;

  /// 从持久化值还原；兼容历史写入的枚举名（如 `zhTW`）。未知值回退跟随系统。
  static AppLanguage fromCode(String? value) => AppLanguage.values.firstWhere(
    (item) => item.code == value || item.name == value,
    orElse: () => AppLanguage.system,
  );

  /// 查表实际使用的语言：跟随系统时按系统区域解析。
  static AppLanguage resolve(AppLanguage mode) {
    if (mode != AppLanguage.system) return mode;
    for (final locale in PlatformDispatcher.instance.locales) {
      final tag = locale.toLanguageTag().toLowerCase();
      if (tag.startsWith('zh')) {
        final traditional =
            tag.contains('hant') ||
            tag.contains('-tw') ||
            tag.contains('-hk') ||
            tag.contains('-mo');
        return traditional ? AppLanguage.zhTW : AppLanguage.zh;
      }
      if (tag.startsWith('en')) return AppLanguage.en;
    }
    return switch (PlatformDispatcher.instance.locale.languageCode
        .toLowerCase()) {
      'en' => AppLanguage.en,
      'zh' => AppLanguage.zh,
      _ => AppLanguage.zh,
    };
  }
}

/// 语言自身的本地化名称；跟随系统返回 null，由调用方回退到 `i18n.follow_system`。
String? languageSelfName(AppLanguage mode) => switch (mode) {
  AppLanguage.system => null,
  AppLanguage.zh => '简体中文',
  AppLanguage.zhTW => '繁體中文',
  AppLanguage.en => 'English',
};
