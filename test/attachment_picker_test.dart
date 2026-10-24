import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:mulit_ai_flutter/chat/attachment_picker.dart';
import 'package:mulit_ai_flutter/core/attachment_store.dart';

mixin _PickerSpy on ImagePickerPlatform {
  int? limit;
  var singleCalls = 0;
  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    limit = options.limit;
    expect(options.imageOptions.maxWidth, isNull);
    expect(options.imageOptions.imageQuality, isNull);
    return [];
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    singleCalls++;
    return XFile('/temporary/photo.jpg');
  }
}

class _Picker extends ImagePickerPlatform with _PickerSpy {}

class _AndroidPicker extends ImagePickerAndroid with _PickerSpy {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImagePickerPlatform original;
  const channel = MethodChannel('between_models/attachments');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => original = ImagePickerPlatform.instance);
  tearDown(() {
    ImagePickerPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'iOS picker receives remaining slots before selection, including one',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final picker = _Picker();
      ImagePickerPlatform.instance = picker;
      await pickChatImages(9);
      expect(picker.limit, 9);
      await pickChatImages(3);
      expect(picker.limit, 3);
      await pickChatImages(1);
      expect(picker.singleCalls, 1);
      await expectLater(pickChatImages(0), throwsA(isA<AttachmentException>()));
      expect(picker.singleCalls, 1);
    },
  );

  for (final available in [true, false]) {
    test('Android bounded photo picker available: $available', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final picker = _AndroidPicker();
      ImagePickerPlatform.instance = picker;
      messenger.setMockMethodCallHandler(channel, (_) async => available);
      await pickChatImages(5);
      expect(picker.useAndroidPhotoPicker, isTrue);
      expect(picker.limit, available ? 5 : isNull);
      expect(picker.singleCalls, available ? 0 : 1);
    });
  }

  test(
    'desktop picker uses single selection instead of an ignored limit',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final picker = _Picker();
      ImagePickerPlatform.instance = picker;
      await pickChatImages(9);
      expect(picker.limit, isNull);
      expect(picker.singleCalls, 1);
    },
  );
}
