import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mulit_ai_flutter/core/apple_purchases.dart';
import 'package:mulit_ai_flutter/settings/purchase_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/apple-purchases');
  late ApplePurchases purchases;
  Map<String, Object?> state = {};
  String outcome = 'pending';
  bool failed = false;
  bool disposed = false;
  late List<String> purchaseMethods;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    purchases = ApplePurchases(channel: channel);
    disposed = false;
    state = {
      'enabled': true,
      'ready': true,
      'canUse': false,
      'permanent': false,
      'hadTrial': false,
      'trialAvailable': true,
      'permanentPrice': '¥70.00',
    };
    outcome = 'pending';
    failed = false;
    purchaseMethods = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (failed) throw PlatformException(code: 'failed');
          if (call.method == 'purchase' ||
              call.method == 'claimFreePermanent') {
            purchaseMethods.add(call.method);
            return {'outcome': outcome, 'state': state};
          }
          return state;
        });
  });

  test(
    'free price does not grant access without a verified permanent purchase',
    () async {
      state.addAll({'permanentPrice': '¥0.00', 'permanentFree': true});
      await purchases.refresh();
      expect(purchases.permanentFree, isTrue);
      expect(purchases.canUse, isFalse);
      for (final result in ['cancelled', 'pending']) {
        outcome = result;
        await purchases.claimFreePermanent();
        expect(purchases.canUse, isFalse);
      }
      state.addAll({'canUse': true, 'hadTrial': true});
      outcome = 'success';
      await purchases.claimFreePermanent();
      expect(purchases.outcome, 'purchaseSyncPending');
      state['permanent'] = true;
      await purchases.refresh();
      expect(purchases.outcome, 'success');
      expect(purchaseMethods, everyElement('claimFreePermanent'));
    },
  );

  testWidgets(
    'free claim uses the guarded native action; ended offer does not buy',
    (tester) async {
      state.addAll({'permanentPrice': '¥0.00', 'permanentFree': true});
      await tester.pumpWidget(
        MaterialApp(home: PurchaseScreen(purchases: purchases)),
      );
      await tester.pumpAndSettle();
      expect(find.text('免费领取 7 天试用'), findsNothing);
      expect(find.textContaining('11 月 10 日'), findsNothing);
      state.addAll({'permanentPrice': '¥70.00', 'permanentFree': false});
      outcome = 'offerUnavailable';
      await tester.ensureVisible(find.text('免费领取永久解锁'));
      await tester.tap(find.text('免费领取永久解锁'));
      await tester.pumpAndSettle();
      expect(purchaseMethods, ['claimFreePermanent']);
      expect(purchases.permanent, isFalse);
      expect(find.text('免费领取永久解锁'), findsNothing);
      expect(find.text('永久解锁 · ¥70.00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      purchases.dispose();
      disposed = true;
      debugDefaultTargetPlatformOverride = null;
    },
  );
  tearDown(() {
    if (!disposed) purchases.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('pending approval and cancellation never grant access', () async {
    await purchases.purchase(ApplePurchases.permanentId);
    expect(purchases.canUse, isFalse);
    expect(purchases.outcome, 'pending');
    expect(purchases.price, '¥70.00');
    outcome = 'cancelled';
    await purchases.purchase(ApplePurchases.permanentId);
    expect(purchases.canUse, isFalse);
  });
  test('older native replies cannot roll back a verified purchase', () async {
    state.addAll({'revision': 5, 'canUse': true, 'permanent': true});
    await purchases.refresh();
    state.addAll({'revision': 4, 'canUse': false, 'permanent': false});
    await purchases.refresh();
    expect(purchases.permanent, isTrue);
    expect(purchases.canUse, isTrue);
    // A newer signed revocation must still remove access.
    state['revision'] = 6;
    await purchases.refresh();
    expect(purchases.canUse, isFalse);
  });
  test('background refresh does not erase restore failure feedback', () async {
    failed = true;
    await purchases.restore();
    expect(purchases.error, 'restoreFailed');
    failed = false;
    await purchases.refresh();
    expect(purchases.error, 'restoreFailed');
    state.addAll({'canUse': true, 'permanent': true});
    await purchases.restore();
    expect(purchases.error, isEmpty);
    expect(purchases.outcome, 'restored');
  });
  test(
    'successful purchase without native access never silently unlocks',
    () async {
      outcome = 'success';
      await purchases.purchase(ApplePurchases.permanentId);
      expect(purchases.canUse, isFalse);
      expect(purchases.outcome, 'purchaseSyncPending');
      state.addAll({'canUse': true, 'permanent': true});
      await purchases.refresh();
      expect(purchases.outcome, 'success');
    },
  );
  test(
    'an active trial cannot complete a pending permanent purchase',
    () async {
      state.addAll({'canUse': true, 'hadTrial': true, 'permanent': false});
      outcome = 'success';
      await purchases.purchase(ApplePurchases.permanentId);
      expect(purchases.canUse, isTrue);
      expect(purchases.outcome, 'purchaseSyncPending');
      await purchases.refresh();
      expect(purchases.outcome, 'purchaseSyncPending');
      state['permanent'] = true;
      await purchases.refresh();
      expect(purchases.outcome, 'success');
    },
  );
  testWidgets(
    'verified purchase changes status and removes both purchase buttons',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: PurchaseScreen(purchases: purchases)),
      );
      await tester.pumpAndSettle();
      state.addAll({'revision': 1, 'canUse': true, 'permanent': true});
      outcome = 'success';
      await tester.ensureVisible(find.text('永久解锁 · ¥70.00'));
      await tester.tap(find.text('永久解锁 · ¥70.00'));
      await tester.pumpAndSettle();
      expect(find.text('已永久解锁'), findsOneWidget);
      expect(find.text('免费领取 7 天试用'), findsNothing);
      expect(find.text('永久解锁 · ¥70.00'), findsNothing);
      expect(find.text('购买成功，功能已解锁。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      purchases.dispose();
      disposed = true;
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'timed out restore releases controls and keeps feedback after refresh',
    (tester) async {
      purchases.dispose();
      purchases = ApplePurchases(
        channel: channel,
        restoreTimeout: const Duration(seconds: 2),
      );
      final pending = Completer<Map<String, Object?>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'restore') return pending.future;
            return state;
          });
      await tester.pumpWidget(
        MaterialApp(home: PurchaseScreen(purchases: purchases)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('恢复购买'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复购买'));
      await tester.pump();
      expect(purchases.busy, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(purchases.busy, isFalse);
      expect(purchases.error, 'restoreTimedOut');
      await purchases.refresh();
      await tester.pump();
      expect(purchases.error, 'restoreTimedOut');
      expect(find.textContaining('恢复购买暂未完成'), findsOneWidget);
      // StoreKit can finish later: a newer verified notification still grants access.
      state.addAll({'revision': 3, 'canUse': true, 'permanent': true});
      await purchases.refresh();
      await tester.pump();
      expect(purchases.canUse, isTrue);
      expect(purchases.error, isEmpty);
      expect(purchases.outcome, 'restored');
      pending.complete(state);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      purchases.dispose();
      disposed = true;
      debugDefaultTargetPlatformOverride = null;
    },
  );
  test('only ready native-verified state grants access; failed refresh closes gate', () async {
    state['canUse'] = true;
    state['permanent'] = true;
    expect(await purchases.refresh(), isTrue);
    failed = true;
    expect(await purchases.refresh(), isFalse);
    expect(purchases.ready, isFalse);
    failed = false;
    state['ready'] = false;
    expect(await purchases.refresh(), isFalse);
  });
  test(
    'refund removes access and restore does not restart used trial',
    () async {
      state.addAll({'canUse': true, 'permanent': true, 'hadTrial': true});
      await purchases.refresh();
      state.addAll({
        'canUse': false,
        'permanent': false,
        'trialAvailable': false,
      });
      await purchases.refresh();
      expect(purchases.canUse, isFalse);
      await purchases.restore();
      expect(purchases.outcome, 'nothingToRestore');
      expect(purchases.hadTrial, isTrue);
      expect(purchases.trialAvailable, isFalse);
    },
  );
  test(
    'native disabled debug channel preserves free development behavior',
    () async {
      state = {'enabled': false, 'ready': true, 'canUse': true};
      expect(await purchases.refresh(), isTrue);
      expect(purchases.enabled, isFalse);
    },
  );
  test('other platforms do not invoke Apple billing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    failed = true;
    expect(await purchases.refresh(), isTrue);
    expect(purchases.error, isEmpty);
  });
  testWidgets(
    'expired trial keeps purchase and restore available without charging automatically',
    (tester) async {
      state.addAll({'hadTrial': true, 'trialAvailable': false});
      await tester.pumpWidget(
        MaterialApp(home: PurchaseScreen(purchases: purchases)),
      );
      await tester.pumpAndSettle();
      expect(find.text('试用已结束'), findsOneWidget);
      expect(find.text('免费领取 7 天试用'), findsNothing);
      expect(find.text('永久解锁 · ¥70.00'), findsOneWidget);
      expect(purchases.outcome, isEmpty);
      await tester.ensureVisible(find.text('恢复购买'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复购买'));
      await tester.pumpAndSettle();
      expect(find.text('没有可恢复的有效权益；已领取的试用不会重新开始。'), findsOneWidget);
      expect(purchases.hadTrial, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      purchases.dispose();
      disposed = true;
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
