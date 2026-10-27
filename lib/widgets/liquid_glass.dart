import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// Supports both instant tab tapping and fluid horizontal dragging of the active pill.
class LiquidGlassBottomNavBar extends StatefulWidget {
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
  State<LiquidGlassBottomNavBar> createState() =>
      _LiquidGlassBottomNavBarState();
}

class _LiquidGlassBottomNavBarState extends State<LiquidGlassBottomNavBar> {
  bool _isDragging = false;
  double? _dragAlignX;
  int? _hoverIndex;
  int? _lastHapticIndex;
  double _dragOffsetFromPillLeft = 0.0;

  @override
  void didUpdateWidget(covariant LiquidGlassBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && !_isDragging) {
      _dragAlignX = null;
      _hoverIndex = null;
    }
  }

  void _onDragStart(DragStartDetails details) {
    final count = widget.tabs.length;
    if (count <= 1) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final width = box.size.width;
    const double padding = 4.0;
    final innerWidth = width - (padding * 2);
    final tabWidth = innerWidth / count;
    final maxTravel = innerWidth - tabWidth;

    final touchInnerX =
        (details.localPosition.dx - padding).clamp(0.0, innerWidth);
    final currentPillLeft =
        widget.selectedIndex.clamp(0, count - 1) * tabWidth;

    if (touchInnerX >= currentPillLeft - 10 &&
        touchInnerX <= currentPillLeft + tabWidth + 10) {
      _dragOffsetFromPillLeft =
          (touchInnerX - currentPillLeft).clamp(0.0, tabWidth);
    } else {
      _dragOffsetFromPillLeft = tabWidth / 2.0;
    }

    final pillLeft =
        (touchInnerX - _dragOffsetFromPillLeft).clamp(0.0, maxTravel);
    final alignX = maxTravel > 0 ? -1.0 + (2.0 * pillLeft / maxTravel) : 0.0;
    final hover =
        ((pillLeft + tabWidth / 2.0) / tabWidth).floor().clamp(0, count - 1);

    _isDragging = true;
    _dragAlignX = alignX;
    _hoverIndex = hover;
    _lastHapticIndex = hover;
    setState(() {});
    HapticFeedback.selectionClick();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    final count = widget.tabs.length;
    if (count <= 1) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final width = box.size.width;
    const double padding = 4.0;
    final innerWidth = width - (padding * 2);
    final tabWidth = innerWidth / count;
    final maxTravel = innerWidth - tabWidth;

    final touchInnerX =
        (details.localPosition.dx - padding).clamp(0.0, innerWidth);
    final pillLeft =
        (touchInnerX - _dragOffsetFromPillLeft).clamp(0.0, maxTravel);
    final alignX = maxTravel > 0 ? -1.0 + (2.0 * pillLeft / maxTravel) : 0.0;
    final hover =
        ((pillLeft + tabWidth / 2.0) / tabWidth).floor().clamp(0, count - 1);

    if (hover != _lastHapticIndex) {
      _lastHapticIndex = hover;
      HapticFeedback.selectionClick();
    }

    setState(() {
      _dragAlignX = alignX;
      _hoverIndex = hover;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    final count = widget.tabs.length;
    int targetIndex = _hoverIndex ?? widget.selectedIndex;

    final velocityX = details.primaryVelocity;
    if (velocityX != null && velocityX.abs() > 300) {
      if (velocityX > 0 && targetIndex < count - 1) {
        targetIndex = (targetIndex + 1).clamp(0, count - 1);
      } else if (velocityX < 0 && targetIndex > 0) {
        targetIndex = (targetIndex - 1).clamp(0, count - 1);
      }
    }

    final finalAlignX = count > 1
        ? -1.0 + (2.0 * targetIndex.clamp(0, count - 1) / (count - 1))
        : 0.0;

    setState(() {
      _isDragging = false;
      _dragAlignX = finalAlignX;
      _hoverIndex = targetIndex;
    });

    widget.onTabSelected(targetIndex);
  }

  void _onDragCancel() {
    if (!_isDragging) return;
    final count = widget.tabs.length;
    final originalAlignX = count > 1
        ? -1.0 + (2.0 * widget.selectedIndex.clamp(0, count - 1) / (count - 1))
        : 0.0;

    setState(() {
      _isDragging = false;
      _dragAlignX = originalAlignX;
      _hoverIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = widget.activeColor ?? const Color(0xFFDF762D);

    final inactiveTextColor = widget.unselectedColor ??
        (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B));
    final inactiveShadow = isDark
        ? Shadow(color: Colors.black.withValues(alpha: 0.85), blurRadius: 4)
        : Shadow(color: Colors.white.withValues(alpha: 0.95), blurRadius: 3);

    final glassFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF1A2332).withValues(alpha: 0.50 * widget.opacity),
              const Color(0xFF0D1420).withValues(alpha: 0.28 * widget.opacity),
            ]
          : [
              Colors.white.withValues(alpha: 0.42 * widget.opacity),
              Colors.white.withValues(alpha: 0.20 * widget.opacity),
            ],
    );

    final radius = BorderRadius.circular(widget.borderRadius);
    const double padding = 4.0;
    final innerRadius = BorderRadius.circular(widget.borderRadius - padding);

    final count = widget.tabs.length;
    final activeIndex = _isDragging
        ? (_hoverIndex ?? widget.selectedIndex)
        : widget.selectedIndex;

    final double alignX = _isDragging && _dragAlignX != null
        ? _dragAlignX!
        : (count > 1
            ? -1.0 +
                (2.0 *
                    widget.selectedIndex.clamp(0, count - 1) /
                    (count - 1))
            : 0.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.45)
                  : const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
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
            filter: ImageFilter.blur(
              sigmaX: widget.blurSigma,
              sigmaY: widget.blurSigma,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: glassFill,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Top specular reflection sheen
                  Positioned(
                    top: 0,
                    left: 20,
                    right: 20,
                    height: 1.2,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(
                                alpha: isDark ? 0.5 : 0.9,
                              ),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Smooth Sliding & Draggable Orange Pill Indicator
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(padding),
                      child: AnimatedAlign(
                        duration: _isDragging
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment(alignX, 0.0),
                        child: FractionallySizedBox(
                          widthFactor: count > 0 ? 1.0 / count : 1.0,
                          heightFactor: 1.0,
                          child: RepaintBoundary(
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
                                    color: const Color(0xFFDF762D).withValues(
                                      alpha: 0.40,
                                    ),
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
                  ),

                  // Interactive Tab Items
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(padding),
                      child: Row(
                        children: List.generate(count, (index) {
                          final tab = widget.tabs[index];
                          final isSelected = activeIndex == index;

                          return Expanded(
                            child: InkWell(
                              borderRadius: innerRadius,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onTabSelected(index);
                              },
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSelected
                                            ? (tab.activeIcon ?? tab.icon)
                                            : tab.icon,
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
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}



/// Tier 1: Frosted Glass Card for content cards (equipment, rentals, settings groups).
/// Combines high legibility with optical blur, subtle specular border, and ambient shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double blurSigma;
  final Color? glowColor;
  final bool isSelected;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 18.0,
    this.padding,
    this.margin,
    this.onTap,
    this.blurSigma = 14.0,
    this.glowColor,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);

    final cardFill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              const Color(0xFF1A2434).withValues(alpha: 0.88),
              const Color(0xFF121B26).withValues(alpha: 0.74),
            ]
          : [
              Colors.white.withValues(alpha: 0.92),
              const Color(0xFFFAF6F0).withValues(alpha: 0.78),
            ],
    );

    final cardBorder = isSelected
        ? const LinearGradient(
            colors: [Color(0xFFFF8A3D), Color(0xFFDF762D)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.06),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.95),
                    const Color(0xFFE2E8F0).withValues(alpha: 0.70),
                  ],
          );

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: cardFill,
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
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          if (isSelected || glowColor != null)
            BoxShadow(
              color: (glowColor ?? const Color(0xFFDF762D))
                  .withValues(alpha: isDark ? 0.25 : 0.18),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: CustomPaint(
        painter: _LiquidGlassBorderPainter(
          borderRadius: borderRadius,
          borderGradient: cardBorder,
          borderWidth: isSelected ? 1.5 : 1.0,
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

/// Frosted Glass Category Pebble for category shortcuts and horizontal selectors.
class GlassCategoryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? activeColor;

  const GlassCategoryPill({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = activeColor ?? const Color(0xFFDF762D);

    final bg = isSelected
        ? primary.withValues(alpha: isDark ? 0.28 : 0.14)
        : isDark
            ? const Color(0xFF1E2838).withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.75);

    final border = isSelected
        ? primary.withValues(alpha: 0.85)
        : isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.95);

    final textColor = isSelected
        ? primary
        : isDark
            ? const Color(0xFFF1F5F9)
            : const Color(0xFF1E293B);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: isSelected ? 1.4 : 1.0),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? primary.withValues(alpha: 0.18)
                    : isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : const Color(0xFF0F172A).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? primary.withValues(alpha: 0.20)
                      : isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : primary.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: isSelected ? primary : textColor),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating Liquid Glass Action Dock (e.g. Item Details sticky bottom bar)
class GlassFloatingDock extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassFloatingDock({
    super.key,
    required this.child,
    this.height = 76,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(28);

    final glassFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF1A2332).withValues(alpha: 0.70),
              const Color(0xFF0D1420).withValues(alpha: 0.48),
            ]
          : [
              Colors.white.withValues(alpha: 0.78),
              const Color(0xFFFAF6F0).withValues(alpha: 0.58),
            ],
    );

    final specularBorder = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.28),
              const Color(0xFFDF762D).withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.12),
            ]
          : [
              Colors.white.withValues(alpha: 0.98),
              const Color(0xFFF3ECE4).withValues(alpha: 0.70),
              const Color(0xFFDF762D).withValues(alpha: 0.28),
            ],
    );

    return SafeArea(
      top: false,
      child: Container(
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.45)
                  : const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: const Color(0xFFDF762D).withValues(alpha: isDark ? 0.16 : 0.10),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24.0, sigmaY: 24.0),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: glassFill,
              ),
              child: CustomPaint(
                painter: _LiquidGlassBorderPainter(
                  borderRadius: 28,
                  borderGradient: specularBorder,
                  borderWidth: 1.2,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function to show a Frosted Glass Modal Bottom Sheet
Future<T?> showFrostedModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? barrierColor,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor ?? Colors.black54,
    builder: (ctx) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24.0, sigmaY: 24.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF1A2332).withValues(alpha: 0.90),
                        const Color(0xFF0D1420).withValues(alpha: 0.82),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.94),
                        const Color(0xFFFFFDFC).withValues(alpha: 0.88),
                      ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.95),
                  width: 1.2,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black54 : Colors.black12,
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  // Specular drag handle
                  Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Flexible(child: builder(ctx)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
