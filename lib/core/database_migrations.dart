import 'package:sqflite/sqflite.dart';

/// Definitions and identifiers come only from the application's schema.
/// The upgrade transaction serializes inspection and additions.
Future<void> addMissingColumns(
  DatabaseExecutor db,
  String table,
  Map<String, String> definitions,
) async {
  final columns = (await db.rawQuery('PRAGMA table_info($table)'))
      .map((row) => row['name'] as String)
      .toSet();
  for (final column in definitions.entries) {
    if (!columns.contains(column.key)) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN ${column.key} ${column.value}',
      );
    }
  }
}
