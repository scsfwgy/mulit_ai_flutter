import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'app_preferences.dart';
import 'ios_style.dart';

/// Visual feedback for a held voice recording. The pointer stays with the
/// composer underneath so releasing or sliding up still ends the gesture.
class VoiceRecordingOverlay extends StatefulWidget {
  const VoiceRecordingOverlay({
    super.key,
    required this.elapsedMs,
    required this.level,
    required this.cancelling,
  });

  final ValueListenable<int> elapsedMs;
  final ValueListenable<double> level;
  final ValueListenable<bool> cancelling;

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
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
      child: ColoredBox(
        color: const Color(0xA0000000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _motion,
                widget.elapsedMs,
                widget.level,
                widget.cancelling,
              ]),
              builder: (context, _) {
                final cancelling = widget.cancelling.value;
                final accent = cancelling
                    ? IosColors.destructive
                    : IosColors.blue;
                final elapsed = widget.elapsedMs.value;
                final seconds = elapsed ~/ 1000;
                final time =
                    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}.${(elapsed % 1000 ~/ 100)}';
                return Container(
                  width: 310,
                  padding: const EdgeInsets.fromLTRB(24, 27, 24, 23),
                  decoration: BoxDecoration(
                    color: IosColors.surface,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: accent.withValues(alpha: .28)),
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
                          cancelling
                              ? CupertinoIcons.xmark
                              : CupertinoIcons.mic_fill,
                          color: accent,
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        tr(cancelling ? '松开取消录音' : '正在录音'),
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
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        tr(cancelling ? '松开取消' : '松开转写 · 上滑取消'),
                        style: TextStyle(
                          color: cancelling
                              ? IosColors.destructive
                              : IosColors.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
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
