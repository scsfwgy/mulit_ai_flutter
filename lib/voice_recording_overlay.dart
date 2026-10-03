import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'app_preferences.dart';
import 'ios_style.dart';

enum VoiceReleaseAction {
  send,
  cancel,
  review;

  static VoiceReleaseAction fromDrag(double horizontalDistance) {
    if (horizontalDistance <= -60) return cancel;
    if (horizontalDistance >= 60) return review;
    return send;
  }
}

/// Feedback only: the composer retains the original held pointer.
class VoiceRecordingOverlay extends StatefulWidget {
  const VoiceRecordingOverlay({
    super.key,
    required this.elapsedMs,
    required this.level,
    required this.releaseAction,
  });

  final ValueListenable<int> elapsedMs;
  final ValueListenable<double> level;
  final ValueListenable<VoiceReleaseAction> releaseAction;

  @override
  State<VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    child: DefaultTextStyle(
      // Root overlay entries have no Scaffold text style; avoid debug underlines.
      style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
        color: IosColors.label,
        fontSize: 17,
        decoration: TextDecoration.none,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: ColoredBox(
          color: const Color(0xA0000000),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 80),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _motion,
                  widget.elapsedMs,
                  widget.level,
                  widget.releaseAction,
                ]),
                builder: (context, _) {
                  final action = widget.releaseAction.value;
                  final accent = switch (action) {
                    VoiceReleaseAction.cancel => IosColors.destructive,
                    VoiceReleaseAction.review =>
                      CupertinoColors.systemGreen.resolveFrom(context),
                    VoiceReleaseAction.send => IosColors.blue,
                  };
                  final elapsed = widget.elapsedMs.value;
                  final seconds = elapsed ~/ 1000;
                  final time =
                      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}.${(elapsed % 1000 ~/ 100)}';
                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 310,
                            padding: const EdgeInsets.fromLTRB(24, 27, 24, 23),
                            decoration: BoxDecoration(
                              color: IosColors.surface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: accent.withValues(alpha: .28),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x50000000),
                                  blurRadius: 32,
                                  offset: Offset(0, 16),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: .15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    switch (action) {
                                      VoiceReleaseAction.cancel =>
                                        CupertinoIcons.xmark,
                                      VoiceReleaseAction.review =>
                                        CupertinoIcons.textformat,
                                      VoiceReleaseAction.send =>
                                        CupertinoIcons.mic_fill,
                                    },
                                    color: accent,
                                    size: 25,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  tr(switch (action) {
                                    VoiceReleaseAction.cancel => '松开取消录音',
                                    VoiceReleaseAction.review => '松开转文字',
                                    VoiceReleaseAction.send => '正在录音',
                                  }),
                                  style: TextStyle(
                                    color: IosColors.label,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                SizedBox(
                                  width: 206,
                                  height: 58,
                                  child: CustomPaint(
                                    painter: _WaveformPainter(
                                      phase: _motion.value,
                                      level: widget.level.value,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  time,
                                  style: TextStyle(
                                    color: IosColors.label,
                                    fontSize: 27,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  tr(switch (action) {
                                    VoiceReleaseAction.cancel => '松开取消',
                                    VoiceReleaseAction.review => '识别后确认发送',
                                    VoiceReleaseAction.send => '松开发送',
                                  }),
                                  style: TextStyle(
                                    color: action == VoiceReleaseAction.send
                                        ? IosColors.secondary
                                        : accent,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _target(
                              icon: CupertinoIcons.xmark,
                              label: '左滑取消',
                              selected: action == VoiceReleaseAction.cancel,
                              accent: IosColors.destructive,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _target(
                              icon: CupertinoIcons.textformat,
                              label: '右滑转文字',
                              selected: action == VoiceReleaseAction.review,
                              accent: CupertinoColors.systemGreen.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _target({
    required IconData icon,
    required String label,
    required bool selected,
    required Color accent,
  }) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
    decoration: BoxDecoration(
      color: selected ? accent : IosColors.surface,
      borderRadius: BorderRadius.circular(32),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 18,
          color: selected ? CupertinoColors.white : IosColors.secondary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            tr(label),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? CupertinoColors.white : IosColors.label,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.phase,
    required this.level,
    required this.color,
  });

  final double phase;
  final double level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 19;
    const barWidth = 4.0;
    final spacing = (size.width - bars * barWidth) / (bars - 1);
    final paint = Paint()..color = color;
    for (var index = 0; index < bars; index++) {
      final centerWeight = 1 - ((index - 9).abs() / 10);
      final pulse =
          (math.sin(phase * math.pi * 2 + index * .63).abs() * .72 + .28);
      final height =
          7 +
          (size.height - 8) *
              (.15 + level.clamp(0, 1) * .85) *
              centerWeight *
              pulse;
      final left = index * (barWidth + spacing);
      final top = (size.height - height) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      phase != oldDelegate.phase ||
      level != oldDelegate.level ||
      color != oldDelegate.color;
}
