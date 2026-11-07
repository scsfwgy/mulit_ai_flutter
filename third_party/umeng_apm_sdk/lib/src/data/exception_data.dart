class ExceptionData {
  // 异常摘要
  String? msg;
  // 异常堆栈
  String? stack;
  // 异常类型
  String? type;
  // 异常级别
  String? level;
  // 重复次数
  int? frequency;
  //自定义属性
  String? extra;

  ExceptionData({
    required String? msg,
    required String? stack,
    required this.type,
    required this.level,
    this.frequency = 1,
    String? extra,
  }) : msg = type ?? 'Error',
       extra = '-',
       stack = safeStack(stack);

  // Never enqueue exception text, custom attributes or local absolute paths.
  static String safeStack(String? stack) => (stack ?? '').split('\n')
      .where((line) => RegExp(r'^#\d+\s+[A-Za-z0-9_.$<> ]+ \(package:[A-Za-z0-9_./-]+\.dart:\d+(?::\d+)?\)$').hasMatch(line))
      .take(20).join('\n');

  void setFrequency() {
    frequency = (frequency ?? 1) + 1;
  }

  Map<String, dynamic> getPreproccessTypeLog() {
    return {
      "msg": msg,
      "stack": stack,
      "type": type,
      "level": level,
      "frequency": frequency,
      "extra": extra
    };
  }

  String getSendTypeLog() {
    List arr = [
      msg ?? '-',
      stack ?? '-',
      type ?? '-',
      level ?? '-',
      frequency ?? '-',
      extra ?? '-'
    ];

    List<dynamic> result = arr.map((val) {
      if (val is String) {
        return Uri.encodeComponent(val.toString());
      }
      return val;
    }).toList();
    return result.join('|');
  }
}
