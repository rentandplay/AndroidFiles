import 'package:flutter/material.dart';

/// A shared scene for glass surfaces across customer and staff destinations.
class AppGlassBackdrop extends StatelessWidget {
  const AppGlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => BackdropGroup(
        child: Stack(children: [
          Positioned.fill(
              child: RepaintBoundary(
                  child: CustomPaint(
            painter: _BackdropPainter(
                Theme.of(context).brightness == Brightness.dark),
          ))),
          child,
        ]),
      );
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.dark);
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..color = dark ? const Color(0xFF0E1825) : const Color(0xFFF4F5F2));
    void glow(Offset center, double radius, Color color, double opacity) {
      final bounds = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
          bounds.intersect(rect),
          Paint()
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0)
              ],
            ).createShader(bounds));
    }

    glow(Offset(size.width, 90), size.width * .95, const Color(0xFFFFA059),
        dark ? .12 : .24);
    glow(Offset(0, size.height * .65), size.width * .9, const Color(0xFF6BB8B1),
        dark ? .09 : .16);
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) => oldDelegate.dark != dark;
}
