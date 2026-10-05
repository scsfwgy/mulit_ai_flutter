import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/app_preferences.dart';
import 'package:mulit_ai_flutter/data.dart';

void main() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  testWidgets('Mac keychain denial has an actionable translated error', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final options = (call.arguments as Map)['options'] as Map;
      expect(options['usesDataProtectionKeychain'], 'false');
      throw PlatformException(code: '-25293', message: 'authorization denied');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    for (final request in [
      ChatStore.instance.apiKey(123),
      ChatStore.instance.searchApiKey('local-test'),
    ]) {
      await expectLater(request, throwsA(isA<KeychainAccessException>()));
    }
    final previous = AppPreferences.instance.language;
    try {
      AppPreferences.instance.language = AppLanguage.en;
      expect(
        tr(const KeychainAccessException().toString()),
        startsWith('Cannot access'),
      );
    } finally {
      AppPreferences.instance.language = previous;
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('phone retains the original secure storage error', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'phone-storage-error');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(
      ChatStore.instance.apiKey(123),
      throwsA(isA<PlatformException>()),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
