import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:umeng_apm_sdk/umeng_apm_sdk.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/core/data.dart';

const umengConsentSetting = 'umeng_diagnostics_consent_v1';
const _distribution = String.fromEnvironment('APP_CHANNEL');
const umengVerification = bool.fromEnvironment('UMENG_DIAGNOSTICS_TEST');

String umengChannel(TargetPlatform platform, String distribution) {
  if (platform == TargetPlatform.iOS) return 'App Store';
  return distribution == 'google_play' || distribution == 'googleplay'
      ? 'googleplay'
      : 'official';
}

bool umengBuildEnabled({
  required bool mobile,
  required bool release,
  required bool verification,
  required String distribution,
}) => mobile && (release || verification) && distribution != 'unknown';

/// New installations share diagnostics; an explicit opt-out is retained.
class UmengDiagnostics extends ChangeNotifier {
  UmengDiagnostics({
    Future<String?> Function()? readConsent,
    Future<void> Function(String)? writeConsent,
    Future<void> Function()? initializeSdk,
    Future<void> Function(bool)? applyCollection,
    bool? enabled,
  }) : _readConsent = readConsent ?? _readStoredPreference,
       _writeConsent =
           writeConsent ??
           ((value) =>
               ChatStore.instance.saveSetting(umengConsentSetting, value)),
       _initializeSdk = initializeSdk ?? _initialize,
       _applyCollection = applyCollection ?? _setCollection,
       enabled = enabled ?? buildEnabled;

  static final instance = UmengDiagnostics();

  static bool get buildEnabled => umengBuildEnabled(
    mobile: supportsUmengDiagnostics,
    release: kReleaseMode,
    verification: umengVerification,
    distribution: _distribution,
  );

  final Future<String?> Function() _readConsent;
  final Future<void> Function(String) _writeConsent;
  final Future<void> Function() _initializeSdk;
  final Future<void> Function(bool) _applyCollection;
  final bool enabled;
  bool? consent;
  bool started = false;
  Future<void>? _starting;
  Future<void> _pending = Future.value();
  bool get collecting => enabled && consent == true;

  Future<void> _update(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> load() => _update(() async {
    if (!enabled) return;
    final value = await _readConsent();
    consent = value != '0';
    await _applyCollection(consent!);
    if (consent == true) await _start();
    notifyListeners();
  });

  Future<void> choose(bool agree) => _update(() async {
    await _writeConsent(agree ? '1' : '0');
    consent = agree;
    await _applyCollection(agree);
    if (agree) await _start();
    notifyListeners();
  });

  static Future<void> _setCollection(bool enabled) async {
    ApmWidgetsFlutterBinding.collectionEnabled = enabled;
    await const MethodChannel('between_models/diagnostics')
        .invokeMethod<void>('setEnabled', enabled);
  }

  static Future<String?> _readStoredPreference() async {
    final value = await const MethodChannel('between_models/diagnostics')
        .invokeMethod<bool>('getEnabled');
    // Keep opt-outs when chat data is cleared; migrate earlier SQLite choices.
    if (value != null) return value ? '1' : '0';
    return ChatStore.instance.setting(umengConsentSetting);
  }

  Future<void> _start() async {
    if (!enabled || consent != true || started) return;
    await (_starting ??= _initializeSdk()
        .then((_) {
          started = true;
        })
        .whenComplete(() => _starting = null));
  }

  static Future<void> _initialize() async {
    final info = await PackageInfo.fromPlatform();
    await UmengCommonSdk.setLogEnabled(umengVerification);
    await UmengCommonSdk.initCommon(
      '6aef1438863270068cba2f0c',
      '6aef14986545637cd63e583c',
      umengChannel(defaultTargetPlatform, _distribution),
    );
    UmengCommonSdk.setPageCollectionModeAuto();
    ApmWidgetsFlutterBinding.collectionEnabled = true;
    UmengApmSdk(
      name: 'mulit_ai_flutter',
      bver: '${info.version}+${info.buildNumber}',
      enableLog: umengVerification,
      enableTrackingPageFps: true,
      enableTrackingPagePerf: true,
      enableTrackingApi: false,
      // The app and its binding already exist; do not create a second root/zone.
      initFlutterBinding: () => WidgetsBinding.instance,
    ).init();
    final previous = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (ApmWidgetsFlutterBinding.collectionEnabled) {
        ExceptionTrace.zonedGuardedErrorHandler(exception: error, stack: stack);
      }
      return previous?.call(error, stack) ?? false;
    };
    if (umengVerification) debugPrint('AI_LINK_UMENG_INITIALIZED');
  }
}
