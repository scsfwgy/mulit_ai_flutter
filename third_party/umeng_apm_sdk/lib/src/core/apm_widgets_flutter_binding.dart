import 'package:flutter/widgets.dart';
import 'package:umeng_apm_sdk/src/utils/helpers.dart';
import 'package:umeng_apm_sdk/src/event/render_event.dart';
import 'package:umeng_apm_sdk/src/core/apm_performance.dart';
import 'package:umeng_apm_sdk/src/event/app_lifecycle_event.dart';
import 'package:umeng_apm_sdk/src/core/apm_log_queue_manager.dart';

class ApmWidgetsFlutterBinding extends WidgetsFlutterBinding {
  static bool _collectionEnabled = false;
  static bool get collectionEnabled => _collectionEnabled;
  static set collectionEnabled(bool enabled) {
    _collectionEnabled = enabled;
    if (!enabled) ApmLogQueueManager.singleInstance.clear();
  }
  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {


    super.handleAppLifecycleStateChanged(state);

    if (collectionEnabled && state == AppLifecycleState.paused) {
      nativeTryCatch(handler: () {
        // 监听应用退至后台
        ApmPerformance.singleInstance
            .pushEvent(ApmAppLifecycleEvent(ApmAppLifecycleState.paused));
      });
    }
  }

  @override
  void handleDrawFrame() {
    super.handleDrawFrame();
    if (!collectionEnabled || renderViews.isEmpty) return;
    nativeTryCatch(handler: () {
      ApmPerformance.singleInstance.pushEvent(ApmRenderEvent(
          ApmRenderEventType.endFrame,
          renderObject: renderViews.first));
    });
  }

  static WidgetsBinding? ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return ApmWidgetsFlutterBinding();
    }
  }
}
