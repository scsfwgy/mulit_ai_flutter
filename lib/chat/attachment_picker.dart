import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:mulit_ai_flutter/core/attachment_store.dart';

/// Platforms without a bounded multi-picker use single selection so the user
/// can never select more items than the remaining slots.
Future<List<XFile>> pickChatImages(int remaining) async {
  if (remaining <= 0) {
    throw const AttachmentException('i18n.attachment_count_limit');
  }
  var limited = defaultTargetPlatform == TargetPlatform.iOS;
  if (ImagePickerPlatform.instance case final ImagePickerAndroid android) {
    android.useAndroidPhotoPicker = true;
    try {
      limited =
          await const MethodChannel('between_models/attachments')
              .invokeMethod<bool>('supportsLimitedPhotoPicker') ??
          false;
    } on PlatformException {
      limited = false;
    } on MissingPluginException {
      limited = false;
    }
  }
  if (limited && remaining > 1) {
    return ImagePicker().pickMultiImage(
      limit: remaining,
      requestFullMetadata: false,
    );
  }
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
  );
  return image == null ? [] : [image];
}
