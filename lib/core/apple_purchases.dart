import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';

/// The native StoreKit bridge is the authority. No entitlement is saved in SQLite.
class ApplePurchases extends ChangeNotifier {
  ApplePurchases({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('between_models/apple_purchases');

  static final instance = ApplePurchases();
  static const permanentId = 'com.maxhall.ailink.permanent_unlock';
  static const trialId = 'com.maxhall.ailink.trial_7_days';
  final MethodChannel _channel;
  bool enabled = supportsApplePurchases;
  bool ready = false;
  bool canUse = !supportsApplePurchases;
  bool permanent = false;
  bool hadTrial = false;
  bool trialAvailable = false;
  bool busy = false;
  String? price;
  DateTime? trialEnd;
  String error = '';
  String outcome = '';
  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started || !supportsApplePurchases) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _apply(call.arguments);
    });
    // Native time advances monotonically. Poll so an open screen updates at expiry.
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh(products: true));
  }

  void _apply(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid purchase state');
    enabled = raw['enabled'] == true;
    ready = raw['ready'] == true;
    canUse = !enabled || (ready && raw['canUse'] == true);
    permanent = raw['permanent'] == true;
    hadTrial = raw['hadTrial'] == true;
    trialAvailable = raw['trialAvailable'] == true;
    price = raw['permanentPrice'] as String?;
    final end = raw['trialEndMs'];
    trialEnd = end is num
        ? DateTime.fromMillisecondsSinceEpoch(end.toInt())
        : null;
    error = raw['error'] as String? ?? '';
    notifyListeners();
  }

  Future<bool> refresh({bool products = false}) async {
    if (!supportsApplePurchases) return true;
    try {
      _apply(
        await _channel.invokeMethod<Object?>('refresh', {'products': products}),
      );
    } catch (_) {
      // A missing/broken bridge on an Apple production app must never unlock it.
      enabled = true;
      ready = false;
      canUse = false;
      error = 'verificationFailed';
      notifyListeners();
    }
    return canUse;
  }

  Future<void> purchase(String id) async {
    if (busy) return;
    busy = true;
    outcome = '';
    notifyListeners();
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'purchase',
        id,
      );
      _apply(reply?['state']);
      outcome = reply?['outcome'] as String? ?? '';
    } catch (_) {
      error = 'purchaseFailed';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (busy) return;
    busy = true;
    outcome = '';
    notifyListeners();
    try {
      _apply(await _channel.invokeMethod<Object?>('restore'));
      outcome = canUse ? 'restored' : 'nothingToRestore';
    } catch (_) {
      error = 'restoreFailed';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
