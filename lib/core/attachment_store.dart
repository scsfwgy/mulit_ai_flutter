import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:mulit_ai_flutter/chat/chat_context.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/core/image_compression.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

class AttachmentException implements Exception {
  const AttachmentException(this.key);
  final String key;
  @override
  String toString() => T(key);
}

class AttachmentStore {
  AttachmentStore([this._directory]);
  static final instance = AttachmentStore();
  static const maxCount = 9;
  static const maxFileBytes = 30 * 1024 * 1024;
  static const maxTotalBytes = 90 * 1024 * 1024;
  // Source photos may exceed the upload limit before compression.
  static const maxImageSourceBytes = 64 * 1024 * 1024;
  Directory? _directory;

  Future<Directory> get directory async => _directory ??= Directory(
    p.join((await getApplicationSupportDirectory()).path, 'chat_attachments'),
  );

  Future<File> file(ChatAttachment attachment) async {
    if (!RegExp(r'^[a-f0-9-]{36}\.(jpg|png|gif|webp|pdf|txt|bin)$')
        .hasMatch(attachment.fileName)) {
      throw const AttachmentException('i18n.attachment_unavailable');
    }
    return File(p.join((await directory).path, attachment.fileName));
  }

  static String? _utf8Text(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      if (text.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'))) return null;
      return text;
    } on FormatException {
      return null;
    }
  }

  static String? _binaryMime(List<int> bytes) {
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((value) => value);
    if (starts([0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (starts(ascii.encode('GIF87a')) || starts(ascii.encode('GIF89a'))) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        starts(ascii.encode('RIFF')) &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    if (starts(ascii.encode('%PDF-'))) return 'application/pdf';
    return null;
  }

  Future<Uint8List> _read(File source, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      if (builder.length + chunk.length > limit) {
        throw const AttachmentException('i18n.attachment_too_large');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<ChatAttachment> importFile(
    String path,
    String name, {
    bool imageOnly = false,
  }) async {
    File? destination;
    try {
      final source = File(path);
      final header = await source
          .openRead(0, 16)
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      final originalMime = _binaryMime(header);
      var bytes = await _read(
        source,
        originalMime?.startsWith('image/') == true
            ? maxImageSourceBytes
            : maxFileBytes,
      );
      if (bytes.isEmpty) {
        throw const AttachmentException('i18n.attachment_empty');
      }
      var mime = _binaryMime(bytes);
      var tokens = mime == null || mime == 'application/pdf' ? 4096 : 2048;
      if (mime == null && !imageOnly) {
        final text = _utf8Text(bytes);
        if (text != null) {
          mime = 'text/plain';
          tokens = ChatContext.estimateTokens(text) + 32;
        } else {
          // Unknown bytes are sent as a file. The model or API reports support.
          mime = 'application/octet-stream';
        }
      }
      if (mime == null || imageOnly && !mime.startsWith('image/')) {
        throw const AttachmentException('i18n.attachment_unsupported_type');
      }
      if (mime.startsWith('image/')) {
        try {
          final compressed = await compressChatImage(bytes, mime);
          bytes = compressed.$1;
          mime = compressed.$2;
        } catch (_) {
          throw const AttachmentException('i18n.attachment_image_failed');
        }
      }
      if (bytes.length > maxFileBytes) {
        throw const AttachmentException('i18n.attachment_too_large');
      }
      final extension = switch (mime) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'application/pdf' => 'pdf',
        'text/plain' => 'txt',
        _ => 'bin',
      };
      final attachment = ChatAttachment(
        name: p
            .basename(
              mime == originalMime || !mime.startsWith('image/')
                  ? name
                  : '${p.basenameWithoutExtension(name)}.$extension',
            )
            .replaceAll(RegExp(r'[\x00-\x1f]'), ''),
        fileName: '${const Uuid().v4()}.$extension',
        mimeType: mime,
        size: bytes.length,
        estimatedTokens: tokens,
      );
      await (await directory).create(recursive: true);
      destination = await file(attachment);
      await destination.writeAsBytes(bytes, flush: true);
      return attachment;
    } on FormatException {
      throw const AttachmentException('i18n.attachment_text_encoding');
    } on FileSystemException {
      if (destination != null && await destination.exists()) {
        await destination.delete();
      }
      throw const AttachmentException('i18n.attachment_unavailable');
    }
  }

  static void validateSelection(List<ChatAttachment> attachments) {
    if (attachments.length > maxCount) {
      throw const AttachmentException('i18n.attachment_count_limit');
    }
    if (attachments.any((a) => a.size > maxFileBytes)) {
      throw const AttachmentException('i18n.attachment_too_large');
    }
    if (attachments.fold(0, (sum, a) => sum + a.size) > maxTotalBytes) {
      throw const AttachmentException('i18n.attachment_total_limit');
    }
  }

  Future<Uint8List> read(ChatAttachment attachment) async {
    try {
      final bytes = await _read(await file(attachment), maxFileBytes);
      if (bytes.length != attachment.size ||
          !attachment.isText &&
              !attachment.isGenericFile &&
              _binaryMime(bytes) != attachment.mimeType) {
        throw const AttachmentException('i18n.attachment_unavailable');
      }
      if (attachment.isText) utf8.decode(bytes);
      return bytes;
    } on FormatException {
      throw const AttachmentException('i18n.attachment_text_encoding');
    } on FileSystemException {
      throw const AttachmentException('i18n.attachment_unavailable');
    }
  }

  Future<void> delete(List<ChatAttachment> attachments) async {
    for (final attachment in attachments) {
      final stored = await file(attachment);
      if (await stored.exists()) await stored.delete();
    }
  }

  Future<void> clear() async {
    final root = await directory;
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Only old, unreferenced app-owned files are removed; picker results arriving
  /// during startup and attachments saved by another engine remain untouched.
  Future<void> removeOrphans(Set<String> retained, DateTime before) async {
    final root = await directory;
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is File &&
          !retained.contains(p.basename(entity.path)) &&
          (await entity.lastModified()).isBefore(before)) {
        await entity.delete();
      }
    }
  }
}
