import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// sqflite 只注册了 Android、iOS 和 macOS。Windows 与 Linux 要用 ffi 打开数据库。
bool sqliteUsesFfi(TargetPlatform platform) =>
    platform == TargetPlatform.windows || platform == TargetPlatform.linux;

/// 在任何数据库打开之前调用一次。单元测试不要调用：它会换掉 sqflite 的全局工厂，
/// 测试里的 method channel 桩就不再接到查询。
Future<void> configureDesktopSqlite() async {
  if (kIsWeb || !sqliteUsesFfi(defaultTargetPlatform)) return;
  if (!Platform.isWindows && !Platform.isLinux) return;
  sqfliteFfiInit();
  databaseFactory = await createDesktopDatabaseFactory(
    await getApplicationSupportDirectory(),
  );
}

/// 固定到用户数据目录，避免快捷方式和终端的工作目录改变历史位置。
Future<DatabaseFactory> createDesktopDatabaseFactory(Directory support) async {
  final factory = createDatabaseFactoryFfi();
  await factory.setDatabasesPath(p.join(support.path, 'databases'));
  return factory;
}
