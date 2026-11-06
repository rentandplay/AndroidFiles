import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive card container with hover lift, dynamic glow, subtle scale,
/// and smooth tactile press physics for a true luxury experience.
class HoverLiftCard extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const HoverLiftCard({
    super.key,
    required this.builder,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding = EdgeInsets.zero,
    this.margin,
  });

  @override
  State<HoverLiftCard> createState() => _HoverLiftCardState();
}

class _HoverLiftCardState extends State<HoverLiftCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final translateY = _isPressed
        ? 1.0
        : _isHovered
            ? -5.0
            : 0.0;
    final scale = _isPressed
        ? 0.975
        : _isHovered
            ? 1.015
            : 1.0;

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() {
            _isPressed = true;
            _isHovered = true;
          });
          HapticFeedback.selectionClick();
        },
        onTapUp: (_) {
          setState(() {
            _isPressed = false;
            _isHovered = false;
          });
        },
        onTapCancel: () {
          setState(() {
            _isPressed = false;
            _isHovered = false;
          });
        },
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          margin: widget.margin,
          transform: Matrix4.translationValues(0.0, translateY, 0.0)
            ..scale(scale),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131D2D) : Colors.white,
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _isHovered
                  ? const Color(0xFFDF762D).withValues(alpha: isDark ? 0.60 : 0.45)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE2E8F0)),
              width: _isHovered ? 1.4 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? const Color(0xFFDF762D).withValues(alpha: isDark ? 0.28 : 0.16)
                    : (isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : const Color(0xFF0F172A).withValues(alpha: 0.06)),
                blurRadius: _isHovered ? 16 : 8,
                spreadRadius: _isHovered ? 1 : 0,
                offset: Offset(0, _isHovered ? 7 : 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Padding(
              padding: widget.padding,
              child: widget.builder(context, _isHovered),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps any card or container with a luxury tactile spring animation on tap.
/// When pressed, it scales down smoothly to 0.965, and on release it springs
/// back with a subtle bounce curve, feeling responsive, physical, and premium.
class PremiumPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;
  final bool enableHaptic;
  final BorderRadius? borderRadius;

  const PremiumPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.965,
    this.duration = const Duration(milliseconds: 130),
    this.enableHaptic = true,
    this.borderRadius,
  });

  @override
  State<PremiumPressable> createState() => _PremiumPressableState();
}

class _PremiumPressableState extends State<PremiumPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _controller.forward();
    if (widget.enableHaptic) {
      HapticFeedback.selectionClick();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    _controller.reverse();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    Widget content = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        alignment: Alignment.center,
        child: child,
      ),
      child: widget.child,
    );

    if (!interactive) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: content,
    );
  }
}

/// Staggered slide-up and fade-in entrance for lists, cards, and containers.
/// Gives screens a fluid, cinematic entry when loaded.
class StaggeredSlideFade extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;
  final double slideOffset;

  const StaggeredSlideFade({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.slideOffset = 22.0,
  });

  @override
  State<StaggeredSlideFade> createState() => _StaggeredSlideFadeState();
}

class _StaggeredSlideFadeState extends State<StaggeredSlideFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.slideOffset),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    final totalDelay = widget.delay + Duration(milliseconds: (widget.index * 35).clamp(0, 350));
    Future.delayed(totalDelay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _fadeAnimation.value,
        child: Transform.translate(
          offset: _slideAnimation.value,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Subtle ambient shimmer/pulse effect for badges, tags, or highlight banners.
class PulsingGlowBadge extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final Duration duration;

  const PulsingGlowBadge({
    super.key,
    required this.child,
    this.glowColor = const Color(0xFFDF762D),
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<PulsingGlowBadge> createState() => _PulsingGlowBadgeState();
}

class _PulsingGlowBadgeState extends State<PulsingGlowBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.25, end: 0.65).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: widget.glowColor.withValues(alpha: _glowAnimation.value * 0.35),
              blurRadius: 10 + (_glowAnimation.value * 6),
              spreadRadius: 1,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
