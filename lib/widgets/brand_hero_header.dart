import 'package:flutter/material.dart';
import 'premium_animations.dart';

/// Custom painter that renders the signature deep midnight navy backdrop with
/// flowing luminous orange and amber waves, matching the Rent & Play luxury hero design.
class NavyOrangeWavePainter extends CustomPainter {
  const NavyOrangeWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Deep Midnight Navy Background Gradient
    final baseGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF030814),
        Color(0xFF071224),
        Color(0xFF0B1D3A),
      ],
      stops: [0.0, 0.45, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = baseGradient);

    // 2. Ambient Warm Orange Radial Glow in Top Right
    final glowCenter = Offset(size.width * 0.88, size.height * 0.35);
    final glowShader = RadialGradient(
      center: Alignment.topRight,
      radius: 0.95,
      colors: [
        const Color(0xFFFF7A1A).withValues(alpha: 0.45),
        const Color(0xFFDF762D).withValues(alpha: 0.22),
        const Color(0xFF071224).withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.50, 1.0],
    ).createShader(Rect.fromCircle(center: glowCenter, radius: size.width * 0.75));
    canvas.drawRect(rect, Paint()..shader = glowShader);

    // 3. Primary Luminous Orange 3D Wave Ribbon
    final ribbonPath = Path();
    ribbonPath.moveTo(size.width * 0.54, size.height * 0.48);
    ribbonPath.cubicTo(
      size.width * 0.68, size.height * 0.36,
      size.width * 0.80, size.height * 0.36,
      size.width * 1.06, size.height * 0.62,
    );
    ribbonPath.lineTo(size.width * 1.08, size.height * 0.96);
    ribbonPath.cubicTo(
      size.width * 0.86, size.height * 0.76,
      size.width * 0.70, size.height * 0.68,
      size.width * 0.54, size.height * 0.48,
    );
    ribbonPath.close();

    final ribbonGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomRight,
      colors: [
        Color(0x00FF8A3D),
        Color(0xFFFF9E58),
        Color(0xFFFF7A1A),
        Color(0xFFDF762D),
        Color(0xFFBA4708),
      ],
      stops: [0.0, 0.22, 0.50, 0.80, 1.0],
    ).createShader(rect);

    canvas.drawPath(
      ribbonPath,
      Paint()
        ..shader = ribbonGradient
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // 4. Secondary Floating Upper Ribbon Accent
    final accentPath = Path();
    accentPath.moveTo(size.width * 0.68, size.height * 0.22);
    accentPath.cubicTo(
      size.width * 0.78, size.height * 0.16,
      size.width * 0.88, size.height * 0.24,
      size.width * 1.08, size.height * 0.46,
    );
    accentPath.lineTo(size.width * 1.10, size.height * 0.40);
    accentPath.cubicTo(
      size.width * 0.90, size.height * 0.18,
      size.width * 0.80, size.height * 0.12,
      size.width * 0.70, size.height * 0.18,
    );
    accentPath.close();

    final accentGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0x00FFFFFF),
        Color(0x55FFCBA4),
        Color(0x33DF762D),
        Color(0x00000000),
      ],
    ).createShader(rect);

    canvas.drawPath(accentPath, Paint()..shader = accentGradient);

    // 5. Specular Crest Highlight Line along the wave crest
    final crestPath = Path();
    crestPath.moveTo(size.width * 0.56, size.height * 0.48);
    crestPath.cubicTo(
      size.width * 0.70, size.height * 0.38,
      size.width * 0.82, size.height * 0.38,
      size.width * 1.04, size.height * 0.62,
    );

    final crestPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
        colors: [
          Color(0x00FFFFFF),
          Color(0xDDFFF1E0),
          Color(0x88FFA86B),
          Color(0x00DF762D),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ).createShader(rect);

    canvas.drawPath(crestPath, crestPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A standalone background container that renders the blue and orange header art.
class NavyOrangeHeroBackground extends StatelessWidget {
  final Widget? child;
  final double? height;

  const NavyOrangeHeroBackground({
    super.key,
    this.child,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const NavyOrangeWavePainter(),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: child,
      ),
    );
  }
}

/// Pronounced organic S-wave clipper that separates the dark hero
/// from the white body content on the Home screen, matching the user reference photo.
class HomeCurvedTopClipper extends CustomClipper<Path> {
  const HomeCurvedTopClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final path = Path();

    const leftY = 46.0;
    const crestY = 2.0;
    const valleyY = 32.0;
    const rightY = 26.0;

    path.moveTo(0, leftY);
    path.cubicTo(
      w * 0.04, crestY + 12,
      w * 0.08, crestY,
      w * 0.35, crestY,
    );
    path.cubicTo(
      w * 0.58, crestY,
      w * 0.72, valleyY,
      w * 0.84, valleyY,
    );
    path.cubicTo(
      w * 0.92, valleyY,
      w * 0.97, valleyY - 2,
      w, rightY,
    );
    path.lineTo(w, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant HomeCurvedTopClipper oldClipper) => false;
}

/// Clips the BOTTOM of the Browse hero header into the exact organic S-wave from the reference mockup:
/// The white wave sits tightly right under the category chips (gap ~4dp under 'All'),
/// slopes down into a gentle valley (depth ~22dp under 'Sports'),
/// and curves up to the right edge (depth ~10dp under 'Tech Rental').
class BrowseHeroBottomWaveClipper extends CustomClipper<Path> {
  const BrowseHeroBottomWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();

    // Fitted directly from the user reference mockup:
    // Chips bottom is positioned at (h - 24.0).
    final leftY = h - 20.0;
    final valleyY = h - 2.0;
    final rightY = h - 14.0;

    path.moveTo(0, 0);
    path.lineTo(w, 0);
    path.lineTo(w, rightY);
    path.cubicTo(
      w * 0.96, rightY - 1.0,
      w * 0.90, valleyY - 8.0,
      w * 0.84, valleyY - 3.0,
    );
    path.cubicTo(
      w * 0.74, valleyY,
      w * 0.60, valleyY,
      w * 0.44, leftY + 12.0,
    );
    path.cubicTo(
      w * 0.28, leftY + 4.0,
      w * 0.12, leftY,
      0, leftY,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant BrowseHeroBottomWaveClipper oldClipper) => false;
}

/// Glowing orange gradient pill button for the dark hero bar.
class HeroLoginButton extends StatelessWidget {
  final VoidCallback onPressed;

  const HeroLoginButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumPressable(
      onTap: onPressed,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF8533),
              Color(0xFFE46618),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE46618).withValues(alpha: 0.45),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.login_rounded, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Login',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pill search bar for the Browse page matching the uploaded design:
/// white rounded container with orange search icon, hint text, and separate filter button.
class BrowseHeroSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Widget? trailing;
  final String hintText;

  const BrowseHeroSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.trailing,
    this.hintText = 'Search equipment',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFFE46618),
                  size: 22,
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 18, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

/// Category chip for the dark hero header on Browse:
/// Active: glowing orange gradient pill with white checkmark
/// Inactive: crisp white pill with dark text
class BrowseCategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const BrowseCategoryChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumPressable(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 38,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 18,
          vertical: 0,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFF8533), Color(0xFFE46618)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF1E2B3E).withValues(alpha: 0.85),
                          const Color(0xFF142032).withValues(alpha: 0.75),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.95),
                          const Color(0xFFFFF9F3).withValues(alpha: 0.85),
                        ],
                ),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : const Color(0xFFE2D9CF).withValues(alpha: 0.8),
                  width: 1.1,
                ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFE46618).withValues(alpha: 0.40)
                  : (isDark
                      ? Colors.black.withValues(alpha: 0.25)
                      : const Color(0xFF0F172A).withValues(alpha: 0.05)),
              blurRadius: isSelected ? 8 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A)),
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                fontSize: 13,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
