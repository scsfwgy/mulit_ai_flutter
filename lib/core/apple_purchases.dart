import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:mulit_ai_flutter/core/app_platform.dart';

/// The native StoreKit bridge is the authority. No entitlement is saved in SQLite.
class ApplePurchases extends ChangeNotifier {
  ApplePurchases({
    MethodChannel? channel,
    this.queryTimeout = const Duration(seconds: 30),
    this.restoreTimeout = const Duration(seconds: 45),
  }) : _channel =
           channel ?? const MethodChannel('between_models/apple_purchases');

  static final instance = ApplePurchases();
  static const permanentId = 'com.maxhall.ailink.permanent_unlock';
  static const trialId = 'com.maxhall.ailink.trial_7_days';
  final MethodChannel _channel;
  final Duration queryTimeout;
  final Duration restoreTimeout;
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
  String _operationError = '';
  String _pendingPurchaseId = '';
  int _revision = -1;
  bool _disposed = false;
  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started || !supportsApplePurchases) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && !_disposed) _apply(call.arguments);
    });
    // Native time advances monotonically. Poll so an open screen updates at expiry.
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh(products: true));
  }

  void _apply(Object? raw) {
    if (_disposed) return;
    if (raw is! Map) throw const FormatException('Invalid purchase state');
    final revision = raw['revision'];
    if (revision is num) {
      if (revision.toInt() < _revision) return;
      _revision = revision.toInt();
    }
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
    // Background StoreKit notifications must not erase a failed restore's
    // feedback. A later verified entitlement can complete a timed-out restore.
    if (_operationError == 'restoreTimedOut' && canUse) {
      _operationError = '';
      outcome = 'restored';
    }
    if (outcome == 'purchaseSyncPending' &&
        (_pendingPurchaseId == permanentId ? permanent : canUse)) {
      outcome = 'success';
    }
    error = _operationError.isNotEmpty
        ? _operationError
        : raw['error'] as String? ?? '';
    notifyListeners();
  }

  Future<bool> refresh({bool products = false}) async {
    if (!supportsApplePurchases) return true;
    try {
      _apply(
        await _channel
            .invokeMethod<Object?>('refresh', {'products': products})
            .timeout(queryTimeout),
      );
    } on TimeoutException {
      if (_disposed) return canUse;
      // A timeout is not a signed revocation of the last verified snapshot.
      error = _operationError.isNotEmpty ? _operationError : 'queryTimedOut';
      notifyListeners();
    } catch (_) {
      if (_disposed) return false;
      // A missing/broken bridge on an Apple production app must never unlock it.
      enabled = true;
      ready = false;
      canUse = false;
      permanent = false;
      error = _operationError.isNotEmpty
          ? _operationError
          : 'verificationFailed';
      notifyListeners();
    }
    return canUse;
  }

  Future<void> purchase(String id) async {
    if (busy) return;
    busy = true;
    outcome = '';
    _pendingPurchaseId = id;
    _operationError = '';
    error = '';
    notifyListeners();
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>(
        'purchase',
        id,
      );
      if (_disposed) return;
      _apply(reply?['state']);
      outcome = reply?['outcome'] as String? ?? '';
      if (outcome == 'success' && !(id == permanentId ? permanent : canUse)) {
        outcome = 'purchaseSyncPending';
      }
    } catch (_) {
      _operationError = error = 'purchaseFailed';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> restore() async {
    if (busy) return;
    busy = true;
    outcome = '';
    _pendingPurchaseId = '';
    _operationError = '';
    error = '';
    notifyListeners();
    try {
      final reply = await _channel
          .invokeMethod<Object?>('restore')
          .timeout(restoreTimeout);
      if (_disposed) return;
      _apply(reply);
      outcome = canUse ? 'restored' : 'nothingToRestore';
    } on TimeoutException {
      _operationError = error = 'restoreTimedOut';
    } catch (_) {
      _operationError = error = 'restoreFailed';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
