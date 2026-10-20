import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

/// 安装一个空的本地数据库桩：所有查询返回空结果集，写入为 no-op。
///
/// 用途：让依赖 `ChatStore` 的页面在 widget 测试里渲染出「空状态」，而不必
/// 复刻 SQLite 语义。`PRAGMA user_version` 返回的值与 `ChatStore` 的
/// `version: 5` 一致，因此不会触发建表或迁移。
///
/// [settings] 可选：提供 `settings` 表的初始键值。传入的 Map 会被**按引用**
/// 持有，测试中途修改它即可模拟「手机改了设置」（例如切换界面语言）后后台
/// 再次读取的效果。
///
/// 需要已初始化的测试 binding；在 `testWidgets` 内部调用即可，普通 `test()`
/// 里只要事先调过 `TestWidgetsFlutterBinding.ensureInitialized()` 同样可用。
void installEmptyDatabaseStub({
  Map<String, String>? settings,
  List<Map<String, Object?>>? providers,
}) {
  const channel = MethodChannel('com.tekartik.sqflite');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(channel, (call) async {
    final args = call.arguments is Map
        ? Map<String, Object?>.from(call.arguments as Map)
        : <String, Object?>{};
    switch (call.method) {
      case 'getDatabasesPath':
        return '/test';
      case 'openDatabase':
        return 1;
      case 'query':
        final sql = args['sql'] as String? ?? '';
        if (sql.contains('user_version')) {
          return [
            {'user_version': 5},
          ];
        }
        if (providers != null && sql.contains('FROM providers')) {
          return providers;
        }
        // sqflite 的 query/rawQuery 只把 `sql` 与 `arguments` 发到通道，
        // 没有 `table` / `whereArgs`，所以按 SQL 文本 + 参数值匹配。
        if (settings != null && sql.contains('settings')) {
          final arguments = args['arguments'] as List? ?? const <Object?>[];
          for (final argument in arguments) {
            if (argument is String && settings.containsKey(argument)) {
              return [
                {'value': settings[argument]},
              ];
            }
          }
        }
        return <Map<String, Object?>>[];
      case 'insert':
        return 1;
      case 'update':
      case 'delete':
        return 0;
      case 'execute':
      case 'close':
        return null;
    }
    throw StateError('Unexpected database operation: ${call.method}');
  });

  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// 切换 sqflite 到 MethodChannel 实现，使 [installEmptyDatabaseStub] 生效。
///
/// 只需在套件开始时调用一次：sqflite 每次重新赋值都会打印一条警告。
void useSqflitePluginFactory() {
  databaseFactory = databaseFactorySqflitePlugin;
}
