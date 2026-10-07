import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

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
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: ColoredBox(
          color: const Color(0xA0000000),
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
              final bottom = MediaQuery.paddingOf(context).bottom;
              return Stack(
                fit: StackFit.expand,
                children: [
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 180),
                      child: Center(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final diameter = math.min(
                              300.0,
                              math.min(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              ),
                            );
                            return SizedBox(
                              key: const ValueKey('voice-recording-circle'),
                              width: diameter,
                              height: diameter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                decoration: BoxDecoration(
                                  color: IosColors.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: accent.withValues(alpha: .3),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x40000000),
                                      blurRadius: 32,
                                      offset: Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: 300,
                                    height: 300,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: .15,
                                            ),
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
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          T(switch (action) {
                                            VoiceReleaseAction.cancel =>
                                              'i18n.release_to_cancel_recording',
                                            VoiceReleaseAction.review =>
                                              'i18n.release_to_transcribe',
                                            VoiceReleaseAction.send => 'i18n.recording',
                                          }),
                                          style: TextStyle(
                                            color: IosColors.label,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: 188,
                                          height: 44,
                                          child: CustomPaint(
                                            painter: _WaveformPainter(
                                              phase: _motion.value,
                                              level: widget.level.value,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          time,
                                          style: TextStyle(
                                            color: IosColors.label,
                                            fontSize: 26,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          T(switch (action) {
                                            VoiceReleaseAction.cancel => 'i18n.release_to_cancel',
                                            VoiceReleaseAction.review =>
                                              'i18n.review_the_transcript_before_sending',
                                            VoiceReleaseAction.send => 'i18n.release_to_send',
                                          }),
                                          style: TextStyle(
                                            color:
                                                action ==
                                                    VoiceReleaseAction.send
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
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 180 + bottom,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 100 + bottom,
                          child: ClipPath(
                            clipper: const _SendAreaClipper(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    CupertinoColors.white.withValues(
                                      alpha: action == VoiceReleaseAction.send
                                          ? .5
                                          : .18,
                                    ),
                                    CupertinoColors.white.withValues(
                                      alpha: .08,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: 100,
                          child: Row(
                            children: [
                              Expanded(
                                child: _target(
                                  label: T('i18n.slide_left_to_cancel'),
                                  selected: action == VoiceReleaseAction.cancel,
                                  accent: IosColors.destructive,
                                  right: false,
                                ),
                              ),
                              const SizedBox(width: 28),
                              Expanded(
                                child: _target(
                                  label: T('i18n.slide_right_to_transcribe'),
                                  selected: action == VoiceReleaseAction.review,
                                  accent: CupertinoColors.systemGreen
                                      .resolveFrom(context),
                                  right: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _target({
    required String label,
    required bool selected,
    required Color accent,
    required bool right,
  }) => ClipPath(
    clipper: _VoiceTargetClipper(right: right),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      color: selected ? accent : CupertinoColors.white.withValues(alpha: .16),
      alignment: Alignment.center,
      padding: const EdgeInsets.only(bottom: 12),
      child: Transform.rotate(
        angle: right ? .16 : -.16,
        child: Text(
          T(label),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.white.withValues(alpha: selected ? 1 : .85),
          ),
        ),
      ),
    ),
  );
}

class _VoiceTargetClipper extends CustomClipper<Path> {
  const _VoiceTargetClipper({required this.right});
  final bool right;

  @override
  Path getClip(Size size) {
    double x(double fraction) => size.width * (right ? 1 - fraction : fraction);
    final h = size.height;
    return Path()
      ..moveTo(x(0), h * .3)
      ..quadraticBezierTo(x(.38), h * .08, x(.78), h * .02)
      ..cubicTo(x(1.04), 0, x(1.08), h * .66, x(.78), h * .72)
      ..quadraticBezierTo(x(.36), h * .77, x(0), h)
      ..close();
  }

  @override
  bool shouldReclip(_VoiceTargetClipper oldClipper) =>
      oldClipper.right != right;
}

class _SendAreaClipper extends CustomClipper<Path> {
  const _SendAreaClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, size.height * .35)
    ..quadraticBezierTo(
      size.width / 2,
      -size.height * .18,
      size.width,
      size.height * .35,
    )
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_SendAreaClipper oldClipper) => false;
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
