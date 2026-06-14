import 'dart:math' as math;
import 'package:flutter/material.dart';

class PointerPill extends StatelessWidget {
  const PointerPill({
    super.key,
    required this.child,
    this.color,
    this.height = 40,
    this.pointerWidth = 16,
    this.smoothness = 3.0,
  });

  final Widget child;
  final Color? color;
  final double height;
  final double pointerWidth;
  final double smoothness;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PointerPillPainter(
        color: color ?? Theme.of(context).colorScheme.surface,
        pointerWidth: pointerWidth,
        smoothness: smoothness,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: height / 2.5,
          right: height / 1.75,
          top: 8,
          bottom: 8,
        ),
        child: child,
      ),
    );
  }
}

class _PointerPillPainter extends CustomPainter {
  final Color color;
  final double pointerWidth;
  final double smoothness;

  _PointerPillPainter({
    required this.color,
    required this.pointerWidth,
    this.smoothness = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    final r = size.height / 2;
    final s = smoothness;

    final x = size.width - pointerWidth;
    final y = size.height / 2;

    final path = Path()
      ..moveTo(r, 0)
      // Top edge
      ..lineTo(x - s, 0)
      // Smooth top-right vertex
      ..quadraticBezierTo(x, 0, x + s, s)
      // Approach tip
      ..lineTo(size.width - s, y - s)
      // Smooth tip
      ..quadraticBezierTo(size.width, y, size.width - s, y + s)
      // Lower side
      ..lineTo(x + s, size.height - s)
      // Smooth bottom-right vertex
      ..quadraticBezierTo(x, size.height, x - s, size.height)
      // Bottom edge
      ..lineTo(r, size.height)
      // Left semicircle
      ..arcTo(
        Rect.fromCircle(center: Offset(r, r), radius: r),
        math.pi / 2,
        math.pi,
        false,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerPillPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointerWidth != pointerWidth;
}
