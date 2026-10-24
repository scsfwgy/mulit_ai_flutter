import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mulit_ai_flutter/core/sqlite_desktop.dart';

void main() {
  test('only Windows and Linux open SQLite through ffi', () {
    expect(sqliteUsesFfi(TargetPlatform.windows), isTrue);
    expect(sqliteUsesFfi(TargetPlatform.linux), isTrue);
    expect(sqliteUsesFfi(TargetPlatform.macOS), isFalse);
    expect(sqliteUsesFfi(TargetPlatform.android), isFalse);
    expect(sqliteUsesFfi(TargetPlatform.iOS), isFalse);
  });

  test('desktop database persists across working directories', () async {
    final root = await Directory.systemTemp.createTemp('ai-link-sqlite-');
    final originalDirectory = Directory.current;
    addTearDown(() async {
      Directory.current = originalDirectory;
      await root.delete(recursive: true);
    });
    final support = Directory(p.join(root.path, 'support'));
    final firstLaunch = await Directory(p.join(root.path, 'launch-a')).create();
    final secondLaunch = await Directory(p.join(root.path, 'launch-b'))
        .create();

    Directory.current = firstLaunch;
    final firstFactory = await createDesktopDatabaseFactory(support);
    final databasePath = p.join(
      await firstFactory.getDatabasesPath(),
      'model_chat.db',
    );
    expect(databasePath, p.join(support.path, 'databases', 'model_chat.db'));
    final first = await firstFactory.openDatabase(databasePath);
    try {
      await first.execute('CREATE TABLE settings (value TEXT)');
      await first.rawInsert('INSERT INTO settings VALUES (?)', [
        'saved history',
      ]);
    } finally {
      await first.close();
    }

    Directory.current = secondLaunch;
    final secondFactory = await createDesktopDatabaseFactory(support);
    final secondPath = p.join(
      await secondFactory.getDatabasesPath(),
      'model_chat.db',
    );
    expect(secondPath, databasePath);
    final second = await secondFactory.openDatabase(secondPath);
    try {
      expect(await second.rawQuery('SELECT value FROM settings'), [
        {'value': 'saved history'},
      ]);
    } finally {
      await second.close();
    }
    expect(
      await Directory(p.join(firstLaunch.path, '.dart_tool')).exists(),
      isFalse,
    );
    expect(
      await Directory(p.join(secondLaunch.path, '.dart_tool')).exists(),
      isFalse,
    );
  });
}
