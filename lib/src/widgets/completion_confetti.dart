import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A short burst of independently moving confetti pieces for task completion.
class CompletionConfetti extends StatefulWidget {
  const CompletionConfetti({super.key});

  @override
  State<CompletionConfetti> createState() => _CompletionConfettiState();
}

class _CompletionConfettiState extends State<CompletionConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => CustomPaint(
        key: const Key('completion-confetti-particles'),
        painter: _ConfettiPainter(progress: _controller.value),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress});

  final double progress;

  static const _colors = [
    Color(0xFFFFC107),
    Color(0xFFE91E63),
    Color(0xFF03A9F4),
    Color(0xFF4CAF50),
    Color(0xFF9C27B0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final fade = 1 - ((progress - .72) / .28).clamp(0.0, 1.0);
    for (var index = 0; index < 72; index++) {
      final seed = index + 1.0;
      final fromLeft = index.isEven;
      final launchX = fromLeft ? size.width * .15 : size.width * .85;
      final spread = ((index * 37) % 100) / 100 - .5;
      final x =
          launchX +
          spread * size.width * (0.55 + progress * .55) +
          math.sin(progress * 14 + seed) * (10 + index % 7 * 3);
      final launchHeight = 18 + (index % 7) * 14.0;
      final y =
          size.height -
          launchHeight -
          progress * (size.height * (.52 + (index % 6) * .05)) +
          progress * progress * size.height * .62;
      final rotation = progress * (8 + index % 6) * (fromLeft ? 1 : -1) + seed;
      final paint = Paint()
        ..color = _colors[index % _colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      if (index % 3 == 0) {
        canvas.drawCircle(Offset.zero, 3 + index % 4, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: 5 + index % 7,
              height: 10 + index % 8,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
