import 'package:flutter/foundation.dart';

/// Runtime capabilities use the host platform, not the shared iOS UI theme.
bool get isDesktopApp =>
    !kIsWeb &&
    const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ].contains(defaultTargetPlatform);

bool get supportsApplePurchases =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get supportsSystemVoice =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get supportsWatchCompanion =>
    !kIsWeb &&
    const [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ].contains(defaultTargetPlatform);

bool get supportsCameraCapture => supportsWatchCompanion;
bool get supportsImagePickerRecovery =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// mobile_scanner 只在 Android、iOS 和 macOS 注册。Windows 与 Linux 不能打开扫码页。
bool get supportsQrScan =>
    !kIsWeb &&
    const [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform);

bool get supportsIncomingShare => supportsWatchCompanion;
