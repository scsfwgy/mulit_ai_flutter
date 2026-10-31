import 'dart:async';

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/chat_draft.dart';
import 'package:mulit_ai_flutter/core/data.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Serialized local checkpoints. The epoch prevents late writes after data clear.
class ChatDraftStore {
  ChatDraftStore({ChatStore? store}) : store = store ?? ChatStore.instance;
  final ChatStore store;
  String? _epoch;
  Future<void> _tail = Future.value();
  int _writes = 0;
  bool get isBusy => _writes != 0;

  Future<bool> refreshEpoch() async {
    await _tail.catchError((_) {});
    final epoch = await (await store.db).transaction((txn) async {
      final rows = await txn.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['chat_draft_epoch'],
      );
      if (rows.isNotEmpty) return rows.single['value'] as String;
      final value = const Uuid().v4();
      await txn.insert('settings', {'key': 'chat_draft_epoch', 'value': value});
      return value;
    });
    final changed = _epoch != null && _epoch != epoch;
    _epoch = epoch;
    return changed;
  }

  Future<ChatDraft> read(String key) async {
    _validateKey(key);
    await _tail.catchError((_) {});
    return ChatDraft.decode(await store.setting(key));
  }

  void _validateKey(String key) {
    if (!RegExp(r'^chat_draft:(topic:[1-9][0-9]*|new:[0-9]+)$').hasMatch(key)) {
      throw const FormatException('Draft key');
    }
  }

  Future<void> save(String key, ChatDraft draft, {String? moveFrom}) {
    _validateKey(key);
    if (moveFrom != null) _validateKey(moveFrom);
    AttachmentStore.validateSelection(draft.attachments);
    final value = draft.encode();
    final epoch = _epoch;
    _writes++;
    final operation = _tail.catchError((_) {}).then((_) async {
      await (await store.db).transaction((txn) async {
        final rows = await txn.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['chat_draft_epoch'],
        );
        if (epoch == null || rows.isEmpty || rows.single['value'] != epoch) {
          return;
        }
        final id = int.parse(key.split(':').last);
        final table = key.startsWith('chat_draft:topic:')
            ? 'topics'
            : 'projects';
        if (id != 0 &&
            (await txn.query(
              table,
              columns: ['id'],
              where: 'id = ?',
              whereArgs: [id],
            )).isEmpty) {
          return;
        }
        if (draft.isEmpty) {
          await txn.delete('settings', where: 'key = ?', whereArgs: [key]);
        } else {
          await txn.insert('settings', {
            'key': key,
            'value': value,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (moveFrom != null && moveFrom != key) {
          await txn.delete('settings', where: 'key = ?', whereArgs: [moveFrom]);
        }
      });
    });
    _tail = operation.whenComplete(() => _writes--);
    return _tail;
  }
}
