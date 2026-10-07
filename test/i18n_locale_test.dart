import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/core/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppPreferences.instance.language = AppLanguage.zh);

  test('繁体解析到显式 Hant locale，简体与英文不受影响', () {
    // 只登记 `zh` 时，`basicLocaleListResolution` 会把 `zh-Hant-TW` 归一到
    // `zh`，框架内置控件（复制、取消等）退回简体文案。
    expect(
      basicLocaleListResolution(
        const [Locale('zh', 'TW')],
        AppPreferences.supportedLocales,
      ),
      AppPreferences.traditionalChinese,
    );
    expect(
      basicLocaleListResolution(
        const [Locale('zh', 'HK')],
        AppPreferences.supportedLocales,
      ),
      AppPreferences.traditionalChineseHongKong,
    );
    expect(
      basicLocaleListResolution(
        const [Locale('zh')],
        AppPreferences.supportedLocales,
      ),
      const Locale('zh'),
    );
    expect(
      basicLocaleListResolution(
        const [Locale('en')],
        AppPreferences.supportedLocales,
      ),
      const Locale('en'),
    );
  });

  test('澳门系统 locale 也解析到繁体，框架内置控件不回退简体', () async {
    // 平台上报不带脚本标签的 `zh-MO`。框架的 `getMaterialTranslation` 对没有
    // 脚本标签的 `zh` 只在国家为 HK/TW 时返回繁体，所以必须靠 `supportedLocales`
    // 里的 `zh_Hant_MO` 把它接住——只登记 `zh` 时复制按钮会显示「复制」。
    expect(
      basicLocaleListResolution(
        const [Locale('zh', 'MO')],
        AppPreferences.supportedLocales,
      ),
      AppPreferences.traditionalChineseMacao,
    );
    // 平台也可能直接上报带脚本的 `zh-Hant-MO`。
    expect(
      basicLocaleListResolution(
        const [
          Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'MO',
          ),
        ],
        AppPreferences.supportedLocales,
      ),
      AppPreferences.traditionalChineseMacao,
    );

    // 端到端取一次框架文案，确认台/港/澳都拿到繁体复制按钮。
    for (final locale in [
      AppPreferences.traditionalChinese,
      AppPreferences.traditionalChineseHongKong,
      AppPreferences.traditionalChineseMacao,
    ]) {
      final resolved = basicLocaleListResolution(
        [locale],
        AppPreferences.supportedLocales,
      );
      final material = await GlobalMaterialLocalizations.delegate.load(
        resolved,
      );
      expect(material.copyButtonLabel, '複製', reason: '$resolved');
    }

    final simplified = await GlobalMaterialLocalizations.delegate.load(
      const Locale('zh'),
    );
    expect(simplified.copyButtonLabel, '复制');
  });

  test('AppPreferences.locale 与 supportedLocales 对齐', () {
    expect(AppPreferences.instance.language, AppLanguage.zh);
    expect(AppPreferences.instance.locale, const Locale('zh'));

    AppPreferences.instance.language = AppLanguage.zhTW;
    expect(AppPreferences.instance.locale, AppPreferences.traditionalChinese);
    expect(
      AppPreferences.supportedLocales,
      contains(AppPreferences.instance.locale),
    );

    AppPreferences.instance.language = AppLanguage.en;
    expect(AppPreferences.instance.locale, const Locale('en'));

    AppPreferences.instance.language = AppLanguage.system;
    expect(AppPreferences.instance.locale, isNull);
  });

  test('AppLanguage 持久化值可往返', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromCode(language.code), language);
    }
    // 兼容历史写入的枚举名。
    expect(AppLanguage.fromCode('zhTW'), AppLanguage.zhTW);
    expect(AppLanguage.fromCode(null), AppLanguage.system);
  });
}
