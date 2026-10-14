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
