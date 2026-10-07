import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/watch/watch_chat.dart';

import 'i18n_assets.dart';
import 'sqflite_stub.dart';

const _channel = MethodChannel('between_models/watch_worker');

/// 模拟原生侧向后台 worker 投递一次 `process` 请求。
///
/// 后台入口通过 `channel.setMethodCallHandler` 注册处理函数，只有把消息推进
/// 入站通道才能触发它。
Future<void> _sendProcess(Map<String, Object?> arguments) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall('process', arguments),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_channel.name, data, (_) {});
}

/// 轮询等待某个条件成立（真实异步，不用 FakeAsync）。
Future<void> _waitUntil(bool Function() done) async {
  for (var attempt = 0; attempt < 200 && !done(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 手表后台是原生新建的独立 FlutterEngine，前台的静态文案表不会共享过去。
/// 后台入口必须在发出 `ready` 之前自行读取语言偏好并载入资源，否则回传手表
/// 的错误文案会是裸 key（`i18n.invalid_recording_or_recording_exceeds` 之类）。
///
/// 这里用 `test()` 而不是 `testWidgets()`：`testWidgets` 跑在 FakeAsync 里，
/// 平台通道（资源读取、sqflite 桩）的真实异步回调不会被推进，`I18n.load`
/// 会永远挂起。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useSqflitePluginFactory);

  test('watch worker loads translations before announcing ready', () async {
    installEmptyDatabaseStub();
    // 从「前台从未载入」的状态开始，模拟后台 engine 的真实起点。
    I18n.resetForTesting();
    addTearDown(seedI18nForTests);

    var readySeen = false;
    bool? loadedAtReady;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'ready') {
        readySeen = true;
        loadedAtReady = I18n.loaded;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    startWatchWorker();
    await _waitUntil(() => readySeen);

    expect(readySeen, isTrue, reason: '后台入口没有发出 ready');
    expect(loadedAtReady, isTrue, reason: 'ready 之前未载入文案表');

    const key = 'i18n.invalid_recording_or_recording_exceeds';
    expect(I18n.lookup(key), isNot(key), reason: '文案表载入后仍返回裸 key');
  });

  test('watch worker follows a phone language change on later requests', () async {
    // 手机当前是英文；测试中途改这个 Map 模拟「用户把手机切成中文」。
    final settings = <String, String>{'app_language': 'en'};
    installEmptyDatabaseStub(settings: settings);
    I18n.resetForTesting();
    addTearDown(seedI18nForTests);

    final published = <Map<String, Object?>>[];
    var readySeen = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'ready') readySeen = true;
      if (call.method == 'publish') {
        published.add(Map<String, Object?>.from(call.arguments as Map));
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    startWatchWorker();
    await _waitUntil(() => readySeen);
    expect(readySeen, isTrue, reason: '后台入口没有发出 ready');
    expect(I18n.current.code, 'en', reason: 'worker 未按手机语言以英文启动');

    // `kind` 不在购买校验列表里，会直接走到「请求无效」分支并回传错误文案，
    // 不需要网络与真实凭据，因此适合用来观察当前语言。
    await _sendProcess({'id': 'r1', 'kind': 'bogus'});
    expect(published.single['stage'], 'error');
    expect(
      published.single['error'],
      'Invalid watch request',
      reason: '首次请求未使用启动时的英文文案',
    );

    // iPhone 的 AppleWatchBridge 会持续复用同一个后台 engine：
    // 切换语言后再次请求，文案必须跟着变。
    settings['app_language'] = 'zh';
    await _sendProcess({'id': 'r2', 'kind': 'bogus'});
    expect(
      published.last['error'],
      '手表请求无效',
      reason: '手机切换语言后后台仍返回旧语言文案',
    );
  });
}
