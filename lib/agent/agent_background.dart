import 'package:flutter/services.dart';

/// Keeps the current process eligible to continue an Agent run after the
/// screen locks. Desktop builds have no handler and ignore the request.
class AgentBackground {
  static const _channel = MethodChannel('between_models/agent_background');

  static Future<void> acquire(String title) async {
    try {
      await _channel.invokeMethod<void>('begin', {'title': title});
    } catch (_) {
      // A missing desktop handler or a rejected system budget must not stop
      // the run. The loop continues for as long as the process stays alive.
    }
  }

  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('end');
    } catch (_) {}
  }
}
