import 'package:flutter/material.dart';

class MirquovaMark extends StatelessWidget {
  const MirquovaMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3478F6), Color(0xFF22D3EE), Color(0xFF8B5CF6)],
        ),
      ),
      child: Text(
        'M',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.52,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
