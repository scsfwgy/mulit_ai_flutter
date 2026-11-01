import 'package:flutter/services.dart';

/// Requests finite background time on iOS. Android and desktop have no handler;
/// the Agent continues only for as long as the system lets the process run.
class AgentBackground {
  static const _channel = MethodChannel('between_models/agent_background');

  static Future<void> acquire(String title) async {
    try {
      await _channel.invokeMethod<void>('begin', {'title': title});
    } catch (_) {
      // A missing platform handler or a rejected system budget must not stop
      // the run. The loop continues for as long as the process stays alive.
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('end');
    } catch (_) {}
  }
}
