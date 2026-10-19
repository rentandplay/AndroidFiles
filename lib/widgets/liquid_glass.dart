import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS 27 Liquid Glass Container
/// Provides realistic optical refraction, specular highlights, frosted blur,
/// and responsive depth for light and dark environments.
class LiquidGlassContainer extends StatelessWidget {
  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.blurSigma = 16.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.glowColor,
    this.customGradient,
    this.borderGradient,
    this.elevation = 0,
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final Color? glowColor;
  final Gradient? customGradient;
  final Gradient? borderGradient;
  final double elevation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Fluid liquid glass fill colors with very subtle warm orange/amber tint
    final defaultGradient = customGradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1E2635).withValues(alpha: 0.82),
                  const Color(0xFF131A24).withValues(alpha: 0.68),
                ]
              : [
                  const Color(0xFFFFFDFC).withValues(alpha: 0.92),
                  const Color(0xFFFAF4ED).withValues(alpha: 0.74),
                ],
        );

    // Specular border highlights with subtle warm amber refraction
    final defaultBorderGradient = borderGradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.45, 1.0],
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.32),
                  const Color(0xFF856A54).withValues(alpha: 0.20),
                  (glowColor ?? const Color(0xFFDF762D)).withValues(alpha: 0.35),
                ]
              : [
                  Colors.white.withValues(alpha: 0.98),
                  const Color(0xFFF3ECE4).withValues(alpha: 0.70),
                  (glowColor ?? const Color(0xFFDF762D)).withValues(alpha: 0.28),
                ],
        );

    final radius = BorderRadius.circular(borderRadius);

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: defaultGradient,
      ),
      child: child,
    );

    if (blurSigma > 0) {
      content = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(borderRadius: radius, child: content);
    }

    Widget body = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // Soft ambient drop shadow with faint warm amber hint
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.38)
                : const Color(0xFF2C1808).withValues(alpha: 0.06),
            blurRadius: 18 + elevation * 4,
            offset: Offset(0, 8 + elevation * 2),
            spreadRadius: -2,
          ),
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withValues(alpha: isDark ? 0.22 : 0.14),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: CustomPaint(
        painter: _LiquidGlassBorderPainter(
          borderRadius: borderRadius,
          borderGradient: defaultBorderGradient,
          borderWidth: 1.2,
        ),
        child: content,
      ),
    );

    if (onTap != null) {
      body = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: body,
        ),
      );
    }

    return body;
  }
}

/// Paints the ultra-crisp liquid glass specular border
class _LiquidGlassBorderPainter extends CustomPainter {
  _LiquidGlassBorderPainter({
    required this.borderRadius,
    required this.borderGradient,
    this.borderWidth = 1.0,
  });

  final double borderRadius;
  final Gradient borderGradient;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(borderWidth / 2),
      Radius.circular(borderRadius),
    );

    final paint = Paint()
      ..shader = borderGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_LiquidGlassBorderPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.borderGradient != borderGradient ||
      oldDelegate.borderWidth != borderWidth;
}

/// Ambient mesh glow background with very subtle warm orange/amber atmospheric orbs
class LiquidAmbientBackdrop extends StatelessWidget {
  const LiquidAmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Solid theme base with subtle warm porcelain/obsidian undertone
        Positioned.fill(
          child: Container(
            color: isDark ? const Color(0xFF0D1219) : const Color(0xFFFBF8F5),
          ),
        ),

        // Glowing fluid orb - Top Right (Warm Brand Amber Glow)
        Positioned(
          top: -110,
          right: -70,
          child: IgnorePointer(
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark
                            ? const Color(0xFFDF762D)
                            : const Color(0xFFFFB273))
                        .withValues(alpha: isDark ? 0.18 : 0.26),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Glowing fluid orb - Center Left (Warm Peach / Golden Nectar Glow)
        Positioned(
          top: 280,
          left: -90,
          child: IgnorePointer(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFFFD4A8))
                        .withValues(alpha: isDark ? 0.10 : 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Glowing fluid orb - Bottom Right (Soft Warm Apricot Aura)
        Positioned(
          bottom: -70,
          right: -50,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark
                            ? const Color(0xFFE26B1E)
                            : const Color(0xFFFFE0C8))
                        .withValues(alpha: isDark ? 0.10 : 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          right: -60,
          child: IgnorePointer(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark
                            ? const Color(0xFF818CF8)
                            : const Color(0xFFDDD6FE))
                        .withValues(alpha: isDark ? 0.09 : 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Child content layer
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Represents a single tab in the [LiquidGlassBottomNavBar].
class LiquidGlassTab {
  final String label;
  final IconData icon;
  final IconData? activeIcon;

  const LiquidGlassTab({
    required this.label,
    required this.icon,
    this.activeIcon,
  });
}

/// iOS 27 Liquid Glass Bottom Navigation Bar
/// Inspired by the pure Flutter optical refraction architecture (Jaxon Evans).
/// Renders true optical refraction, specular lens bevel, horizontal light reflection,
/// and high-translucency glass body so content flowing underneath is clearly blurred and refracted.
class LiquidGlassBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final List<LiquidGlassTab> tabs;
  final ValueChanged<int> onTabSelected;
  final double opacity;
  final Color? activeColor;
  final Color? unselectedColor;
  final double borderRadius;
  final double blurSigma;

  const LiquidGlassBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.tabs,
    required this.onTabSelected,
    this.opacity = 1.0,
    this.activeColor,
    this.unselectedColor,
    this.borderRadius = 32.0,
    this.blurSigma = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = activeColor ?? const Color(0xFFDF762D);

    // Text & icon colors adapt to light/dark background for crystal clear readability
    final inactiveTextColor = unselectedColor ??
        (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B));
    final inactiveShadow = isDark
        ? Shadow(color: Colors.black.withValues(alpha: 0.85), blurRadius: 4)
        : Shadow(color: Colors.white.withValues(alpha: 0.95), blurRadius: 3);

    // High-translucency single-layer liquid glass fill
    final glassFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF1A2332).withValues(alpha: 0.50 * opacity),
              const Color(0xFF0D1420).withValues(alpha: 0.28 * opacity),
            ]
          : [
              Colors.white.withValues(alpha: 0.42 * opacity),
              Colors.white.withValues(alpha: 0.20 * opacity),
            ],
    );

    final radius = BorderRadius.circular(borderRadius);
    const double padding = 4.0;
    // Perfect concentric corner radius: R_inner = R_outer - padding
    final innerRadius = BorderRadius.circular(borderRadius - padding);

    final count = tabs.length;
    final double alignX = count > 1
        ? -1.0 + (2.0 * selectedIndex.clamp(0, count - 1) / (count - 1))
        : 0.0;

    return Container(
      height: 62,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // Soft ambient drop shadow
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          // Warm amber caustic refraction glow
          BoxShadow(
            color: primary.withValues(alpha: isDark ? 0.20 : 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: glassFill,
              // Single clean outer specular border (no duplicate inner lines)
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.85),
                width: 1.2,
              ),
            ),
            child: Stack(
              children: [
                // Top specular reflection sheen (crescent highlight along upper edge)
                Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  height: 1.2,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: isDark ? 0.5 : 0.9),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Smooth Sliding Orange Pill Indicator
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(padding),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment(alignX, 0.0),
                      child: FractionallySizedBox(
                        widthFactor: 1.0 / count,
                        heightFactor: 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFF8533),
                                Color(0xFFDF762D),
                              ],
                            ),
                            borderRadius: innerRadius,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.45),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFDF762D)
                                    .withValues(alpha: 0.40),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Interactive Tab Items
                Row(
                  children: List.generate(count, (index) {
                    final tab = tabs[index];
                    final isSelected = selectedIndex == index;

                    return Expanded(
                      child: InkWell(
                        borderRadius: radius,
                        onTap: () => onTabSelected(index),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  isSelected
                                      ? (tab.activeIcon ?? tab.icon)
                                      : tab.icon,
                                  key: ValueKey('${tab.label}-$isSelected'),
                                  size: 21,
                                  color: isSelected
                                      ? Colors.white
                                      : inactiveTextColor,
                                  shadows: isSelected
                                      ? [
                                          const Shadow(
                                            color: Color(0x66000000),
                                            blurRadius: 3,
                                          ),
                                        ]
                                      : [inactiveShadow],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tab.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : inactiveTextColor,
                                  shadows: isSelected
                                      ? [
                                          const Shadow(
                                            color: Color(0x66000000),
                                            blurRadius: 3,
                                          ),
                                        ]
                                      : [inactiveShadow],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

