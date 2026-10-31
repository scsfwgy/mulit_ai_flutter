import 'dart:io';

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:path/path.dart' as p;

/// Reveal the selected file on macOS/Windows, or its folder on Linux.
Future<void> revealFileInManager(File source) async {
  if (!await source.exists()) {
    throw const AttachmentException('i18n.attachment_unavailable');
  }
  try {
    final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', ['-R', source.path]);
    } else if (Platform.isWindows) {
      result = await Process.run('explorer', ['/select,${source.path}']);
    } else {
      result = await Process.run('xdg-open', [p.dirname(source.path)]);
    }
    // Explorer reports 1 even when the folder opens.
    if (result.exitCode != 0 && !Platform.isWindows) {
      throw const AttachmentException('i18n.library_path_failed');
    }
  } on ProcessException {
    throw const AttachmentException('i18n.library_path_failed');
  }
}
