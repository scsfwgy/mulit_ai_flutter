import 'dart:async';

import 'i18n_assets.dart';

/// `flutter test` 的全局钩子：整套测试运行前预载文案表，使 `T`/`F` 可用。
///
/// 这里刻意 **不** 调用 `TestWidgetsFlutterBinding.ensureInitialized()`。
/// 该 binding 会把 `HttpOverrides.global` 换成「所有 HTTP 请求返回 400」的
/// 桩，而本仓库有大量协议测试依赖真实回环 `HttpServer`；一旦提前初始化
/// binding，这些测试会全部因 400 失败。`testWidgets` 会在需要时自行初始化
/// binding，因此 widget 测试不受影响。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  seedI18nForTests();
  await testMain();
}
