import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'liquid_glass_optics.dart';
import 'app_glass_backdrop.dart';
export 'liquid_glass_optics.dart' show LiquidGlassScope;

LinearGradient _clearGlassFill(bool dark, {double opacity = 1}) =>
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? [
              const Color(0xFF23354A).withValues(alpha: .30 * opacity),
              const Color(0xFF142235).withValues(alpha: .15 * opacity),
            ]
          : [
              Colors.white.withValues(alpha: .34 * opacity),
              const Color(0xFFFFF9F1).withValues(alpha: .16 * opacity),
            ],
    );

/// Frosted & Liquid Glass Surface Container
/// Engineered to prevent Impeller dark-edge vignette smudges and black-alpha
/// gradient interpolation while delivering crisp specular borders, inner top-edge
/// light refraction, and soft outer elevation depth.
class LiquidGlassContainer extends StatelessWidget {
  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.blurSigma = 0.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.glowColor,
    this.customGradient,
    this.borderGradient,
    this.elevation = 0,
    this.filterBackdrop = true,
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
  final bool filterBackdrop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clear = LiquidGlassScope.of(context);

    // Multi-stop luminous frosted glass fill (never interpolates through black)
    final defaultGradient = customGradient ??
        (clear
            ? _clearGlassFill(isDark)
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.55, 1.0],
                colors: isDark
                    ? [
                        const Color(0xFF1E293B).withValues(alpha: 0.94),
                        const Color(0xFF162030).withValues(alpha: 0.90),
                        const Color(0xFF111927).withValues(alpha: 0.88),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.96),
                        const Color(0xFFFFFCF9).withValues(alpha: 0.92),
                        const Color(0xFFFBF5EE).withValues(alpha: 0.88),
                      ],
              ));

    // Directional specular rim: bright top-left light catch, subtle warm edge
    final defaultBorderGradient = borderGradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.24),
                  Colors.white.withValues(alpha: 0.09),
                  (glowColor ?? const Color(0xFFDF762D))
                      .withValues(alpha: 0.22),
                ]
              : [
                  Colors.white,
                  const Color(0xFFEAE2D8).withValues(alpha: 0.85),
                  (glowColor ?? const Color(0xFFDF762D))
                      .withValues(alpha: 0.20),
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

    final shouldFilter = clear && filterBackdrop && blurSigma > 0;
    content = shouldFilter
        ? LiquidGlassOptics(
            borderRadius: borderRadius,
            blurSigma: blurSigma,
            child: content,
          )
        : ClipRRect(borderRadius: radius, child: content);

    Widget body = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.32)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16 + elevation * 3,
            offset: Offset(0, 6 + elevation * 1.5),
            blurStyle: BlurStyle.outer,
          ),
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withValues(alpha: isDark ? 0.18 : 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
              blurStyle: BlurStyle.outer,
            ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _LiquidGlassBorderPainter(
          borderRadius: borderRadius,
          borderGradient: defaultBorderGradient,
          borderWidth: 1.15,
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

    return RepaintBoundary(child: body);
  }
}

/// Paints the crisp liquid glass specular border on the foreground layer
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

/// Luminous ambient backdrop for Frosted & Liquid Glass screens.
/// Uses color-matched zero-alpha stops (never 0x00000000 black transparent)
/// so gradients remain pure, warm, and completely free of grey/black smudges.
class LiquidAmbientBackdrop extends StatelessWidget {
  const LiquidAmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppGlassBackdrop(child: child);
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

/// Floating Frosted & Liquid Glass Bottom Navigation Bar.
/// Renders optical background blur with mirror tile mode (avoiding black edge sampling),
/// outer ambient shadows, specular border highlights, and fluid pill selection.
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
    this.blurSigma = 20.0,
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
    final currentPillLeft = widget.selectedIndex.clamp(0, count - 1) * tabWidth;

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
    final clear = LiquidGlassScope.of(context);
    // A quiet warm material supports the labels; the moving lens carries the
    // stronger orange. Neither color depends on shader output.
    const dockInk = Color(0xFF1C130B);
    final selectedText = clear ? dockInk : Colors.white;
    final inactiveTextColor = widget.unselectedColor ??
        (clear
            ? (isDark ? const Color(0xFFF0F4F8) : const Color(0xFF29323E))
            : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)));
    final dockMaterial = Color.alphaBlend(
      const Color(0xFFFF962E).withValues(alpha: .035),
      (isDark ? const Color(0xFF102033) : Colors.white)
          .withValues(alpha: isDark ? .12 : .10),
    );
    final dockTint = clear
        ? dockMaterial.withValues(alpha: dockMaterial.a * widget.opacity)
        : null;
    final glassFill = clear
        ? null
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF1B2536)
                        .withValues(alpha: .88 * widget.opacity),
                    const Color(0xFF111826)
                        .withValues(alpha: .82 * widget.opacity)
                  ]
                : [
                    Colors.white.withValues(alpha: .90 * widget.opacity),
                    const Color(0xFFFAF5EE)
                        .withValues(alpha: .84 * widget.opacity)
                  ],
          );

    final specularBorder = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.26),
              Colors.white.withValues(alpha: 0.10),
              primary.withValues(alpha: 0.24),
            ]
          : [
              Colors.white,
              const Color(0xFFEAE2D8).withValues(alpha: 0.90),
              primary.withValues(alpha: 0.22),
            ],
    );

    final radius = BorderRadius.circular(widget.borderRadius);
    const double padding = 4.0;
    final innerRadius = BorderRadius.circular(widget.borderRadius - padding);

    final selectionFace = Container(
      decoration: BoxDecoration(
        gradient: clear
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: .20),
                  Colors.white.withValues(alpha: .025),
                  const Color(0xFFFFAD59).withValues(alpha: .12),
                ],
                stops: const [0, .5, 1],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8838), Color(0xFFDF762D)],
              ),
        borderRadius: innerRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: clear ? .65 : .38),
          width: 1,
        ),
        boxShadow: clear
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFFDF762D).withValues(alpha: .30),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                  blurStyle: BlurStyle.outer,
                ),
              ],
      ),
    );
    Widget buildSelectionLens() => clear
        ? LiquidGlassOptics(
            borderRadius: widget.borderRadius - padding,
            blurSigma: 0,
            refraction: 6,
            dispersion: .45,
            bevelWidth: 7,
            surfaceTint: const Color(0xFFFF8E20)
                .withValues(alpha: (isDark ? .86 : .72) * widget.opacity),
            tintBevelWidth: 3.5,
            refractive: true,
            child: selectionFace,
          )
        : selectionFace;

    final count = widget.tabs.length;
    final activeIndex = _isDragging
        ? (_hoverIndex ?? widget.selectedIndex)
        : widget.selectedIndex;

    final double alignX = _isDragging && _dragAlignX != null
        ? _dragAlignX!
        : (count > 1
            ? -1.0 +
                (2.0 * widget.selectedIndex.clamp(0, count - 1) / (count - 1))
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
          boxShadow: clear
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(
                        alpha: clear
                            ? (isDark ? .12 : .04)
                            : (isDark ? .42 : .08)),
                    blurRadius: clear ? 18 : 24,
                    offset: Offset(0, clear ? 4 : 8),
                    blurStyle: BlurStyle.outer,
                  ),
                  BoxShadow(
                    color: primary.withValues(
                        alpha: clear ? .06 : (isDark ? .16 : .08)),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                    blurStyle: BlurStyle.outer,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: LiquidGlassOptics(
            borderRadius: widget.borderRadius,
            blurSigma: clear ? 2 : widget.blurSigma,
            refraction: 11,
            dispersion: .65,
            bevelWidth: 10,
            surfaceTint: dockTint,
            refractive: clear,
            child: CustomPaint(
              foregroundPainter: _LiquidGlassBorderPainter(
                borderRadius: widget.borderRadius,
                borderGradient: specularBorder,
                borderWidth: 1.2,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: glassFill,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Top specular reflection sheen
                    Positioned(
                      top: 0,
                      left: 24,
                      right: 24,
                      height: 1.2,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1),
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(
                                  alpha: isDark ? 0.40 : 0.95,
                                ),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // A stronger orange lens distinguishes the selected tab.
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(padding),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: alignX, end: alignX),
                          duration: _isDragging
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          builder: (context, position, _) => Align(
                            alignment: Alignment(position, 0.0),
                            child: FractionallySizedBox(
                              widthFactor: count > 0 ? 1.0 / count : 1.0,
                              heightFactor: 1.0,
                              child: RepaintBoundary(
                                child: buildSelectionLens(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Interactive Tab Items (crisp icons & labels, no muddy shadows)
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
                                              ? selectedText
                                              : inactiveTextColor,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          tab.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: isSelected
                                                ? selectedText
                                                : inactiveTextColor,
                                            letterSpacing: -0.1,
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
      ),
    );
  }
}

/// Tier 1: Frosted Glass Card for content cards (equipment, rentals, settings groups).
/// Uses a multi-stop frosted surface gradient, crisp foreground specular border,
/// and outer ambient shadow so cards never suffer from Impeller dark-edge smudges.
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
    this.blurSigma = 0.0,
    this.glowColor,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (LiquidGlassScope.of(context)) {
      return LiquidGlassContainer(
        borderRadius: borderRadius,
        padding: padding,
        margin: margin,
        onTap: onTap,
        blurSigma: blurSigma,
        glowColor: glowColor,
        borderGradient: isSelected
            ? const LinearGradient(
                colors: [Color(0xFFFFB47C), Color(0xFFDF762D)])
            : null,
        child: child,
      );
    }
    final radius = BorderRadius.circular(borderRadius);

    final cardFill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.6, 1.0],
      colors: isDark
          ? [
              const Color(0xFF1C2738).withValues(alpha: 0.95),
              const Color(0xFF151F2E).withValues(alpha: 0.92),
              const Color(0xFF111926).withValues(alpha: 0.90),
            ]
          : [
              Colors.white.withValues(alpha: 0.97),
              const Color(0xFFFFFCF9).withValues(alpha: 0.94),
              const Color(0xFFFBF6EF).withValues(alpha: 0.90),
            ],
    );

    final cardBorder = isSelected
        ? const LinearGradient(
            colors: [Color(0xFFFF8A3D), Color(0xFFDF762D)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.5, 1.0],
            colors: isDark
                ? [
                    Colors.white.withValues(alpha: 0.20),
                    Colors.white.withValues(alpha: 0.08),
                    const Color(0xFF334155).withValues(alpha: 0.35),
                  ]
                : [
                    Colors.white,
                    const Color(0xFFE6DFD5).withValues(alpha: 0.85),
                    const Color(0xFFDCD3C8).withValues(alpha: 0.65),
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

    content = ClipRRect(borderRadius: radius, child: content);

    Widget body = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.30)
                : const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
            blurStyle: BlurStyle.outer,
          ),
          if (isSelected || glowColor != null)
            BoxShadow(
              color: (glowColor ?? const Color(0xFFDF762D))
                  .withValues(alpha: isDark ? 0.22 : 0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
              blurStyle: BlurStyle.outer,
            ),
        ],
      ),
      child: CustomPaint(
        foregroundPainter: _LiquidGlassBorderPainter(
          borderRadius: borderRadius,
          borderGradient: cardBorder,
          borderWidth: isSelected ? 1.5 : 1.1,
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

    return RepaintBoundary(child: body);
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

    final bgGradient = isSelected
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    primary.withValues(alpha: 0.28),
                    primary.withValues(alpha: 0.18),
                  ]
                : [
                    const Color(0xFFFFF3E8),
                    const Color(0xFFFEE7D3),
                  ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1E293B).withValues(alpha: 0.92),
                    const Color(0xFF151E2C).withValues(alpha: 0.88),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.96),
                    const Color(0xFFFBF6F0).withValues(alpha: 0.90),
                  ],
          );

    final border = isSelected
        ? primary.withValues(alpha: 0.75)
        : isDark
            ? Colors.white.withValues(alpha: 0.16)
            : const Color(0xFFE5DEC9).withValues(alpha: 0.75);

    final textColor = isSelected
        ? (isDark ? const Color(0xFFFF9E5E) : const Color(0xFFB85012))
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
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: isSelected ? 1.3 : 1.0),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? primary.withValues(alpha: 0.14)
                    : isDark
                        ? Colors.black.withValues(alpha: 0.22)
                        : const Color(0xFF0F172A).withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
                blurStyle: BlurStyle.outer,
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
                      ? primary.withValues(alpha: isDark ? 0.24 : 0.16)
                      : isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : primary.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: isSelected ? primary : textColor,
                ),
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
              const Color(0xFF1B2536).withValues(alpha: 0.90),
              const Color(0xFF111826).withValues(alpha: 0.84),
            ]
          : [
              Colors.white.withValues(alpha: 0.92),
              const Color(0xFFFAF6F0).withValues(alpha: 0.86),
            ],
    );

    final specularBorder = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.26),
              const Color(0xFFDF762D).withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.10),
            ]
          : [
              Colors.white,
              const Color(0xFFEAE2D8).withValues(alpha: 0.85),
              const Color(0xFFDF762D).withValues(alpha: 0.24),
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
                  ? Colors.black.withValues(alpha: 0.40)
                  : const Color(0xFF0F172A).withValues(alpha: 0.07),
              blurRadius: 22,
              offset: const Offset(0, 8),
              blurStyle: BlurStyle.outer,
            ),
            BoxShadow(
              color: const Color(0xFFDF762D)
                  .withValues(alpha: isDark ? 0.14 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
              blurStyle: BlurStyle.outer,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 20.0,
              sigmaY: 20.0,
              tileMode: TileMode.mirror,
            ),
            child: CustomPaint(
              foregroundPainter: _LiquidGlassBorderPainter(
                borderRadius: 28,
                borderGradient: specularBorder,
                borderWidth: 1.2,
              ),
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: glassFill,
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
          filter: ImageFilter.blur(
            sigmaX: 22.0,
            sigmaY: 22.0,
            tileMode: TileMode.mirror,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF1A2332).withValues(alpha: 0.94),
                        const Color(0xFF0F1622).withValues(alpha: 0.90),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.96),
                        const Color(0xFFFFFCF9).withValues(alpha: 0.92),
                      ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.white,
                  width: 1.2,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black54 : Colors.black12,
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                  blurStyle: BlurStyle.outer,
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
