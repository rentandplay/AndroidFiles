import 'liquid_glass.dart';
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
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
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
            ..scaleByDouble(scale, scale, 1.0, 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: LiquidGlassScope.of(context)
                ? Colors.transparent
                : (isDark ? const Color(0xFF131D2D) : Colors.white),
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _isHovered
                  ? const Color(0xFFDF762D)
                      .withValues(alpha: isDark ? 0.60 : 0.45)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE2E8F0)),
              width: _isHovered ? 1.4 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? const Color(0xFFDF762D)
                        .withValues(alpha: isDark ? 0.28 : 0.16)
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
              child: LiquidGlassScope.of(context)
                  ? LiquidGlassContainer(
                      filterBackdrop: false,
                      borderRadius: widget.borderRadius.topLeft.x,
                      child: widget.builder(context, _isHovered))
                  : widget.builder(context, _isHovered),
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

    final totalDelay = widget.delay +
        Duration(milliseconds: (widget.index * 35).clamp(0, 350));
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
              color: widget.glowColor
                  .withValues(alpha: _glowAnimation.value * 0.35),
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

/// A luxury page transitions builder that provides ultra-smooth, fluid
/// screen transitions with subtle slide, scale, and fade.
class FluidPageTransitionsBuilder extends PageTransitionsBuilder {
  const FluidPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final curvedSecondary = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final slideIn = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(curvedAnimation);

    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.04, 0),
    ).animate(curvedSecondary);

    final scaleIn = Tween<double>(
      begin: 0.985,
      end: 1.0,
    ).animate(curvedAnimation);

    final fadeIn = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(curvedAnimation);

    final fadeOut = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(curvedSecondary);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: fadeIn,
            child: ScaleTransition(
              scale: scaleIn,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// An Animated IndexedStack that smoothly animates fade and subtle upward slide
/// when the active tab index changes, while completely preserving the state and
/// scroll positions of all tab views.
class AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 240),
  });

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..value = 1.0;

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<double>(
      begin: 10.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
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
          offset: Offset(0, _slideAnimation.value),
          child: child,
        ),
      ),
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}

/// Spring-pop scale and fade entrance for badges, buttons, cards, and avatars.
class SpringPopEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const SpringPopEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  State<SpringPopEntrance> createState() => _SpringPopEntranceState();
}

class _SpringPopEntranceState extends State<SpringPopEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
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
        child: Transform.scale(
          scale: _scaleAnimation.value,
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Breathing status indicator dot for active rentals, live statuses, and alerts.
class PulsingStatusDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingStatusDot({
    super.key,
    required this.color,
    this.size = 8.0,
  });

  @override
  State<PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
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
      animation: _controller,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: widget.size * _scaleAnimation.value * 1.8,
            height: widget.size * _scaleAnimation.value * 1.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(
                alpha: (1.0 - _opacityAnimation.value) * 0.45,
              ),
            ),
          ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}
