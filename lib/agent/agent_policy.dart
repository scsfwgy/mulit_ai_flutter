import 'dart:convert';

abstract final class AgentPolicy {
  static const maxRounds = 12;
  static const maxCalls = 24;
  static const maxRetries = 2;

  static int initialOutput(int window) => (window ~/ 4).clamp(4096, 16384);
  static int maximumOutput(int window) => (window ~/ 2).clamp(4096, 65536);

  static bool isContinue(String text) => {
    '继续',
    '繼續',
    '继续任务',
    '繼續任務',
    'continue',
    'resume',
  }.contains(text.trim().toLowerCase().replaceAll(RegExp(r'[。.!！]+$'), ''));

  static bool repeating(List<Map<String, dynamic>> steps) {
    if (steps.length < 3) return false;
    final last = steps.sublist(steps.length - 3);
    if (last.every((s) => s['status'] == 'failed')) return true;
    Object? canonical(Object? value) {
      if (value is Map) {
        final keys = value.keys.cast<String>().toList()..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      if (value is List) return value.map(canonical).toList();
      return value;
    }

    final signatures = last
        .map((s) => '${s['name']}:${jsonEncode(canonical(s['arguments']))}')
        .toSet();
    return signatures.length == 1;
  }
}
