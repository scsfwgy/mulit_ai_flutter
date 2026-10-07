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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (failed) throw PlatformException(code: 'failed');
          if (call.method == 'purchase') {
            return {'outcome': outcome, 'state': state};
          }
          return state;
        });
  });
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
