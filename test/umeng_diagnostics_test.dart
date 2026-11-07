import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umeng_apm_sdk/src/data/exception_data.dart';
import 'package:umeng_apm_sdk/umeng_apm_sdk.dart';
import 'package:umeng_apm_sdk/src/core/apm_log_queue_manager.dart';
import 'package:umeng_apm_sdk/src/core/apm_request.dart';
import 'package:umeng_apm_sdk/src/core/apm_shared.dart';
import 'package:mulit_ai_flutter/core/umeng_diagnostics.dart';

void main() {
  test('distribution channels remain separate', () {
    expect(umengChannel(TargetPlatform.android, 'official'), 'official');
    expect(umengChannel(TargetPlatform.android, 'google_play'), 'googleplay');
    expect(umengChannel(TargetPlatform.android, 'googleplay'), 'googleplay');
    expect(umengChannel(TargetPlatform.iOS, 'google_play'), 'App Store');
  });

  test('desktop, development and distributed test builds remain excluded', () {
    bool enabled(bool mobile, bool release, bool verify, String channel) =>
        umengBuildEnabled(
          mobile: mobile,
          release: release,
          verification: verify,
          distribution: channel,
        );
    expect(enabled(false, true, false, 'official'), isFalse);
    expect(enabled(true, false, false, 'official'), isFalse);
    expect(enabled(true, true, false, 'unknown'), isFalse);
    expect(enabled(true, true, false, 'official'), isTrue);
    expect(enabled(true, false, true, ''), isTrue);
  });

  test('new installs start by default; opt-out survives restart', () async {
    String? persisted;
    var starts = 0;
    final changes = <bool>[];
    UmengDiagnostics create() => UmengDiagnostics(
      enabled: true,
      readConsent: () async => persisted,
      writeConsent: (value) async => persisted = value,
      initializeSdk: () async {
        starts++;
      },
      applyCollection: (enabled) async => changes.add(enabled),
    );
    final diagnostics = create();
    await diagnostics.load();
    expect(diagnostics.consent, isTrue);
    expect(starts, 1);
    await diagnostics.choose(false);
    expect(diagnostics.collecting, isFalse);
    expect(persisted, '0');
    expect(changes, [true, false]);
    diagnostics.dispose();
    final restarted = create();
    await restarted.load();
    expect(restarted.collecting, isFalse);
    expect(starts, 1);
    restarted.dispose();
  });

  test(
    'consent is saved before starting; repeated requests share one start',
    () async {
      String? persisted;
      var starts = 0;
      final pending = Completer<void>();
      final diagnostics = UmengDiagnostics(
        enabled: true,
        applyCollection: (_) async {},
        readConsent: () async => persisted,
        writeConsent: (value) async => persisted = value,
        initializeSdk: () {
          expect(persisted, '1');
          starts++;
          return pending.future;
        },
      );
      final first = diagnostics.choose(true);
      final second = diagnostics.choose(true);
      await Future<void>.delayed(Duration.zero);
      expect(starts, 1);
      pending.complete();
      await Future.wait([first, second]);
      await diagnostics.load();
      expect(diagnostics.started, isTrue);
      expect(starts, 1);
      diagnostics.dispose();
    },
  );

  test('failed consent persistence cannot enable collection', () async {
    var starts = 0;
    final diagnostics = UmengDiagnostics(
      enabled: true,
      applyCollection: (_) async {},
      readConsent: () async => null,
      writeConsent: (_) async => throw StateError('storage unavailable'),
      initializeSdk: () async {
        starts++;
      },
    );
    await expectLater(diagnostics.choose(true), throwsStateError);
    expect(starts, 0);
    expect(diagnostics.started, isFalse);
    diagnostics.dispose();
  });

  test(
    'disabling Flutter collection drops queued reports and blocks upload',
    () async {
      final queue = ApmLogQueueManager.singleInstance;
      ApmWidgetsFlutterBinding.collectionEnabled = true;
      for (final type in ReportLogType.values) {
        for (final state in ReportQueueType.values) {
          queue
              .getQueueObject(reportType: type, reportQueueType: state)
              ?.add('private report');
        }
      }
      ApmWidgetsFlutterBinding.collectionEnabled = false;
      for (final type in ReportLogType.values) {
        for (final state in ReportQueueType.values) {
          expect(
            queue.getQueueObject(reportType: type, reportQueueType: state),
            isEmpty,
          );
        }
      }
      expect(await ApmRequest().post(data: null), isFalse);
    },
  );

  test(
    'Flutter diagnostics remove error bodies, attributes and local paths',
    () {
      final data = ExceptionData(
        msg: 'secret-key and chat text https://private.example/v1',
        stack:
            '#0 ChatHome._send (package:mulit_ai_flutter/chat/chat_home.dart:12:3)\n'
            '#1 private (file:///Users/person/private.dart:2:1)\nsecret-key',
        type: 'StateError',
        level: 'Error',
        extra: 'private prompt',
      );
      final report = data.getSendTypeLog();
      expect(data.msg, 'StateError');
      expect(data.stack, contains('package:mulit_ai_flutter'));
      for (final secret in [
        'secret-key',
        'private.example',
        'private prompt',
        'Users',
      ]) {
        expect(report, isNot(contains(Uri.encodeComponent(secret))));
      }
    },
  );
}
