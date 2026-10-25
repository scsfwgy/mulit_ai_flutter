import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:mulit_ai_flutter/core/sqlite_desktop.dart';

void main() {
  test('a newer database is rejected without lowering its version or deleting data', () async {
    final root = await Directory.systemTemp.createTemp(
      'ai-link-newer-database-',
    );
    final factory = await createDesktopDatabaseFactory(root);
    databaseFactory = factory;
    final path = p.join(await factory.getDatabasesPath(), 'model_chat.db');
    final newer = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE future_data (id INTEGER PRIMARY KEY, value TEXT)',
          );
          await db.insert('future_data', {
            'id': 1,
            'value': 'Keep future data',
          });
        },
      ),
    );
    await newer.close();
    await expectLater(
      ChatStore.instance.db,
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('8 to 7'),
        ),
      ),
    );
    final preserved = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      expect(await preserved.getVersion(), 8);
      expect(await preserved.query('future_data'), [
        {'id': 1, 'value': 'Keep future data'},
      ]);
    } finally {
      await preserved.close();
      await root.delete(recursive: true);
    }
  });
}
