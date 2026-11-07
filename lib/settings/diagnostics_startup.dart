import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:umeng_apm_sdk/umeng_apm_sdk.dart';

import 'package:mulit_ai_flutter/core/umeng_diagnostics.dart';

class DiagnosticsStartup extends StatefulWidget {
  const DiagnosticsStartup({super.key, required this.child});
  final Widget child;

  @override
  State<DiagnosticsStartup> createState() => _DiagnosticsStartupState();
}

class _DiagnosticsStartupState extends State<DiagnosticsStartup> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final diagnostics = UmengDiagnostics.instance;
    if (!diagnostics.enabled) return;
    try {
      await diagnostics.load();
      if (mounted && diagnostics.collecting) {
        final route = ModalRoute.of(context);
        if (route != null) {
          ApmNavigatorObserver.singleInstance.didPush(route, null);
        }
      }
    } catch (_) {
      // Diagnostics must not prevent chatting when storage or an SDK fails.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
