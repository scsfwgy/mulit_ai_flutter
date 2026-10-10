import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';

/// Storefront restrictions apply to the iOS App Store and its paired watch.
/// They do not identify the user's nationality or physical location.
class StorefrontPolicy extends ChangeNotifier with WidgetsBindingObserver {
  StorefrontPolicy({
    MethodChannel? channel,
    this.timeout = const Duration(seconds: 5),
  }) : _channel = channel ?? const MethodChannel('between_models/storefront');

  static final instance = StorefrontPolicy();
  final MethodChannel _channel;
  final Duration timeout;
  String? _countryCode;
  int _revision = -1;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _refreshing;

  bool get restricted =>
      supportsApplePurchases && (_countryCode == null || _countryCode == 'CHN');

  static bool isOpenAIModel(String? model) {
    final id = (model ?? '').trim().toLowerCase();
    return id.startsWith('openai/') || id.startsWith('~openai/');
  }

  static bool isOpenAI(String endpoint, {String? presetId, String? model}) {
    if (isOpenAIModel(model)) return true;
    if (presetId?.toLowerCase() == 'openai') return true;
    final host = Uri.tryParse(endpoint.trim())?.host
        .toLowerCase()
        .replaceFirst(RegExp(r'\.+$'), '');
    return host == 'openai.com' || host?.endsWith('.openai.com') == true;
  }

  bool blocks(String endpoint, {String? presetId, String? model}) =>
      restricted && isOpenAI(endpoint, presetId: presetId, model: model);

  void start() {
    if (_started || !supportsApplePurchases) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _apply(call.arguments);
    });
  }

  void _apply(Object? raw) {
    if (_disposed) return;
    if (raw is Map && raw['revision'] is int) {
      final revision = raw['revision'] as int;
      if (revision < _revision) return;
      _revision = revision;
    }
    final code = raw is Map ? raw['countryCode'] : null;
    final normalized = code is String ? code.trim().toUpperCase() : '';
    final country =
        raw is Map &&
            raw['environment'] == 'production' &&
            RegExp(r'^[A-Z]{3}$').hasMatch(normalized)
        ? normalized
        : null;
    if (country != _countryCode) {
      _countryCode = country;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!supportsApplePurchases || _disposed) return;
    start();
    if (_refreshing case final pending?) return pending;
    final pending = _read();
    _refreshing = pending;
    try {
      await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _read() async {
    try {
      final result = await _channel
          .invokeMethod<Object?>('refresh')
          .timeout(timeout);
      _apply(result);
      assert(() {
        debugPrint(
          '[AI Link] Storefront rawCountry=${result is Map ? result['countryCode'] : null} environment=${result is Map ? result['environment'] : null} restricted=$restricted',
        );
        return true;
      }());
    } catch (_) {
      // Never fall back to a remembered overseas storefront after a failure.
      _apply(null);
    }
  }

  Future<void> requireAllowed(
    String endpoint, {
    String? presetId,
    String? model,
  }) async {
    if (!isOpenAI(endpoint, presetId: presetId, model: model)) return;
    await refresh();
    if (blocks(endpoint, presetId: presetId, model: model)) {
      throw const StorefrontRestrictedException();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _apply(null);
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}

class StorefrontRestrictedException implements Exception {
  const StorefrontRestrictedException();
  String get message => T('i18n.openai_storefront_unavailable');
  @override
  String toString() => message;
}

/// Rebuild an open service screen when its available presets change.
mixin StorefrontAware<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    StorefrontPolicy.instance.addListener(_storefrontRebuild);
  }

  void _storefrontRebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    StorefrontPolicy.instance.removeListener(_storefrontRebuild);
    super.dispose();
  }
}
