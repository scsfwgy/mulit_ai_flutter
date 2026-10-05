import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'app_preferences.dart';
import 'ios_style.dart';

/// Paints immediately, then keeps the launch artwork visible until local data
/// and the chat page are ready. The chat stays mounted during the fade-out.
class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.initialize,
    required this.homeBuilder,
  });

  final Future<void> Function() initialize;
  final Widget Function(VoidCallback onReady) homeBuilder;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _initialized = false;
  bool _minimumElapsed = false;
  bool _homeReady = false;
  Timer? _minimumTimer;
  Timer? _removalTimer;
  bool _removed = false;

  bool get _finished => _homeReady && _minimumElapsed;

  @override
  void initState() {
    super.initState();
    _minimumTimer = Timer(const Duration(milliseconds: 900), () {
      setState(() => _minimumElapsed = true);
      _finish();
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
    } catch (_) {
      // ChatHome displays storage failures and remains usable with defaults.
    }
    if (mounted) setState(() => _initialized = true);
  }

  void _ready() {
    if (!mounted || _homeReady) return;
    setState(() => _homeReady = true);
    _finish();
  }

  void _finish() {
    if (!_finished || _removalTimer != null) return;
    _removalTimer = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _removed = true);
    });
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _removalTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_initialized)
        ExcludeSemantics(
          excluding: !_finished,
          child: IgnorePointer(
            ignoring: !_finished,
            child: widget.homeBuilder(_ready),
          ),
        ),
      if (!_removed)
        IgnorePointer(
          ignoring: _finished,
          child: AnimatedOpacity(
            opacity: _finished ? 0 : 1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            child: const AppLaunchArtwork(),
          ),
        ),
    ],
  );
}

class AppLaunchArtwork extends StatelessWidget {
  const AppLaunchArtwork({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: IosColors.background,
    child: DefaultTextStyle(
      style: CupertinoTheme.of(context).textTheme.textStyle,
      child: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: .9 + .1 * value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/branding/ai_link_icon_source.png',
                      width: 96,
                      height: 96,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - value)),
                    child: Column(
                      children: [
                        Text(
                          'AI Link',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.7,
                            color: IosColors.label,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('连接你的 AI'),
                          style: TextStyle(
                            fontSize: 14,
                            color: IosColors.secondary,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(height: 28),
                        CupertinoActivityIndicator(color: IosColors.blue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
