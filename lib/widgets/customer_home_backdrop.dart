import 'package:flutter/material.dart';

/// Vector artwork, painted at the device resolution without a blurred bitmap.
class CustomerHomeHeroBackground extends StatelessWidget {
  const CustomerHomeHeroBackground(
      {super.key, required this.child, this.backdropKey});
  final Widget child;
  final BackdropKey? backdropKey;

  @override
  Widget build(BuildContext context) => BackdropGroup(
      backdropKey: backdropKey,
      child: RepaintBoundary(
        child: ClipRect(
          child: CustomPaint(painter: const _RibbonPainter(), child: child),
        ),
      ));
}

class _RibbonPainter extends CustomPainter {
  const _RibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF091321), Color(0xFF172A41)],
          ).createShader(rect));

    // Both ends leave the canvas. There is no triangular point or blurred edge.
    final ribbon = Path()
      ..moveTo(w * 1.10, -h * .12)
      ..cubicTo(w * .53, -h * .24, w * .49, h * .47, w * .85, h * .64)
      ..cubicTo(w * 1.13, h * .78, w * .97, h * 1.06, w * .58, h * 1.20)
      ..lineTo(w * 1.04, h * 1.28)
      ..cubicTo(w * 1.35, h * .96, w * 1.15, h * .64, w * .96, h * .49)
      ..cubicTo(w * .74, h * .31, w * .78, h * .08, w * 1.14, h * .12)
      ..close();
    canvas.drawPath(
        ribbon,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF7D3119),
              Color(0xFFFFAD68),
              Color(0xFFF3843E),
              Color(0xFFBC481C),
              Color(0xFFFFBE83),
            ],
            stops: [0, .32, .52, .76, 1],
          ).createShader(Rect.fromLTWH(w * .55, 0, w * .55, h)));

    final edge = Path()
      ..moveTo(w * 1.10, -h * .12)
      ..cubicTo(w * .53, -h * .24, w * .49, h * .47, w * .85, h * .64)
      ..cubicTo(w * 1.13, h * .78, w * .97, h * 1.06, w * .58, h * 1.20);
    canvas.drawPath(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..shader = const LinearGradient(
            colors: [Color(0x00FFD8AE), Color(0xEEFFE1BF), Color(0x00FFC384)],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => false;
}

/// Gives the clear cards a real coloured scene to transmit. The body and dock
/// share this scene, rather than placing near-opaque surfaces on plain white.
class CustomerHomeScene extends StatelessWidget {
  const CustomerHomeScene({super.key, required this.child, this.backdropKey});
  final Widget child;
  final BackdropKey? backdropKey;

  @override
  Widget build(BuildContext context) => BackdropGroup(
      backdropKey: backdropKey,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ScenePainter(
                    dark: Theme.of(context).brightness == Brightness.dark),
              ),
            ),
          ),
          child,
        ],
      ));
}

class CustomerHomeTopClipper extends CustomClipper<Path> {
  const CustomerHomeTopClipper();
  // The scene must cover the entire flat bottom of the navy artwork.
  static const overlap = 40.0;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 26)
    ..cubicTo(size.width * .18, 0, size.width * .30, 0, size.width * .49, 14)
    ..cubicTo(size.width * .68, 28, size.width * .82, 35, size.width, 20)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(CustomerHomeTopClipper oldClipper) => false;
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter({required this.dark});
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sceneShape = const CustomerHomeTopClipper().getClip(size);
    canvas.drawPath(
        sceneShape,
        Paint()
          ..color = dark ? const Color(0xFF0D1219) : const Color(0xFFFBF8F5));
    canvas.save();
    canvas.clipPath(sceneShape);
    void pool(Offset center, double radius, Color color, double alpha) {
      final bounds = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
          bounds.intersect(rect),
          Paint()
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0)
              ],
            ).createShader(bounds));
    }

    pool(Offset(size.width * 1.05, 150), size.width * .95,
        const Color(0xFFF39A57), dark ? .27 : .34);
    pool(Offset(-size.width * .12, 530), size.width * .86,
        const Color(0xFF6BB8B1), dark ? .19 : .23);
    pool(Offset(size.width * .94, size.height - 28), size.width * .92,
        const Color(0xFFED9C62), dark ? .25 : .29);
    pool(Offset(0, size.height), size.width * .70, const Color(0xFF8D9DCB),
        dark ? .20 : .22);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.dark != dark;
}
