import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Renders the official 4-color Google "G" logo using vector canvas arcs.
class GoogleLogoIcon extends StatelessWidget {
  const GoogleLogoIcon({
    super.key,
    this.size = 20,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const Color _blue = Color(0xFF4285F4);
  static const Color _red = Color(0xFFEA4335);
  static const Color _yellow = Color(0xFFFBBC05);
  static const Color _green = Color(0xFF34A853);

  double _deg(double degrees) => degrees * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.21;
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // Red top-left / top arc (205° -> 318°)
    paint.color = _red;
    canvas.drawArc(rect, _deg(205), _deg(113), false, paint);

    // Yellow left arc (135° -> 208°)
    paint.color = _yellow;
    canvas.drawArc(rect, _deg(135), _deg(73), false, paint);

    // Green bottom-left / bottom arc (42° -> 138°)
    paint.color = _green;
    canvas.drawArc(rect, _deg(42), _deg(96), false, paint);

    // Blue bottom-right arc (-12° -> 45°)
    paint.color = _blue;
    canvas.drawArc(rect, _deg(-12), _deg(57), false, paint);

    // Horizontal blue crossbar of the "G"
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _blue
      ..isAntiAlias = true;

    final barTop = center.dy - strokeWidth * 0.48;
    final barBottom = center.dy + strokeWidth * 0.48;
    final barLeft = center.dx + size.width * 0.02;
    final barRight = size.width - strokeWidth * 0.06;

    canvas.drawRRect(
      RRect.fromLTRBR(
        barLeft,
        barTop,
        barRight,
        barBottom,
        Radius.circular(strokeWidth * 0.15),
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
