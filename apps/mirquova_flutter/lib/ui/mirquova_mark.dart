import 'package:flutter/material.dart';

/// Matches `android/.../drawable/splash_mark.xml` so launch hands off cleanly.
class MirquovaMark extends StatelessWidget {
  const MirquovaMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3478F6), Color(0xFF22D3EE), Color(0xFF8B5CF6)],
        ),
      ),
      child: CustomPaint(painter: _LetterPainter()),
    );
  }
}

class _LetterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 112;
    final path = Path()
      ..moveTo(28 * unit, 86 * unit)
      ..lineTo(28 * unit, 28 * unit)
      ..lineTo(56 * unit, 60 * unit)
      ..lineTo(84 * unit, 28 * unit)
      ..lineTo(84 * unit, 86 * unit);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_LetterPainter oldDelegate) => false;
}
