import 'package:flutter/services.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';

/// Native inbox entries remain on disk until the new draft has been imported.
class IncomingShare {
  const IncomingShare(this.id, this.files, {this.error});
  final String? error;
  final String id;
  final List<({String path, String name})> files;
  static const channel = MethodChannel('between_models/incoming_share');

  static Future<IncomingShare?> peek() async {
    final value = await channel.invokeMapMethod<String, dynamic>('peek', {
      'language': I18n.current.code,
    });
    if (value == null) return null;
    final files = (value['files'] as List)
        .map(
          (item) => (
            path: item['path'] as String,
            name: item['sharedText'] == true
                ? T('i18n.shared_text_file')
                : item['name'] as String,
          ),
        )
        .toList();
    return IncomingShare(
      value['id'] as String,
      files,
      error: value['error'] as String?,
    );
  }

  Future<List<ChatAttachment>> import(AttachmentStore store) async {
    if (error != null && error!.isNotEmpty) throw AttachmentException(error!);
    final imported = <ChatAttachment>[];
    try {
      if (files.isEmpty || files.length > AttachmentStore.maxCount) {
        throw const AttachmentException('i18n.attachment_count_limit');
      }
      for (final file in files) {
        imported.add(await store.importFile(file.path, file.name));
      }
      AttachmentStore.validateSelection(imported);
      return imported;
    } catch (_) {
      await store.delete(imported);
      rethrow;
    }
  }

  Future<void> acknowledge() => channel.invokeMethod<void>('ack', {'id': id});
}
