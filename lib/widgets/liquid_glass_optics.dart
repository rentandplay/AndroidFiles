import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps the clear material within the customer experience.
class LiquidGlassScope extends InheritedWidget {
  const LiquidGlassScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidGlassScope>() != null;

  @override
  bool updateShouldNotify(LiquidGlassScope oldWidget) => false;
}

/// Filters only the backdrop; the foreground labels and icons stay sharp.
/// Content shares a blur pass; only explicitly selected surfaces use refraction.
class LiquidGlassOptics extends StatefulWidget {
  const LiquidGlassOptics({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blurSigma = 3,
    this.refraction = 5,
    this.dispersion = .65,
    this.refractive = false,
    this.bevelWidth = 10,
    this.surfaceTint,
    this.tintBevelWidth = 0,
  });

  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final double refraction;
  final double dispersion;
  final bool refractive;
  final double bevelWidth;
  final Color? surfaceTint;
  final double tintBevelWidth;

  @override
  State<LiquidGlassOptics> createState() => _LiquidGlassOpticsState();
}

class _LiquidGlassOpticsState extends State<LiquidGlassOptics> {
  static Future<ui.FragmentProgram>? _program;
  static ui.FragmentProgram? _readyProgram;
  ui.FragmentShader? _shader;
  ui.ImageFilter? _blur;
  double? _blurSigma;
  final _boundsKey = GlobalKey();
  Rect? _surfaceBounds;
  Size? _viewportSize;
  bool _measureQueued = false;

  void _measureBoundsAfterLayout() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (!mounted) return;
      final surfaceContext = _boundsKey.currentContext;
      final box = surfaceContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      final view = View.of(surfaceContext!);
      final renderSize =
          surfaceContext.findAncestorRenderObjectOfType<RenderView>()?.size;
      final viewport = renderSize != null && !renderSize.isEmpty
          ? renderSize
          : (MediaQuery.maybeSizeOf(surfaceContext) ??
              view.physicalSize / view.devicePixelRatio);
      if (_surfaceBounds != bounds || _viewportSize != viewport) {
        setState(() {
          _surfaceBounds = bounds;
          _viewportSize = viewport;
        });
      }
    });
  }

  ui.ImageFilter get _blurFilter {
    if (_blur == null || _blurSigma != widget.blurSigma) {
      _blurSigma = widget.blurSigma;
      _blur = ui.ImageFilter.blur(
        sigmaX: widget.blurSigma,
        sigmaY: widget.blurSigma,
        tileMode: ui.TileMode.mirror,
      );
    }
    return _blur!;
  }

  @override
  void initState() {
    super.initState();
    if (widget.refractive && ui.ImageFilter.isShaderFilterSupported) {
      final ready = _readyProgram;
      if (ready != null) {
        _shader = ready.fragmentShader();
      } else {
        _loadShader();
      }
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await (_program ??=
          ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag'));
      _readyProgram = program;
      if (!mounted || !widget.refractive) return;
      setState(() => _shader = program.fragmentShader());
    } catch (error) {
      // The clear material stays usable while an unsupported shader falls back.
      _program = null;
      debugPrint('Liquid glass shader unavailable: $error');
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget tintedChild() {
      final tint = widget.surfaceTint;
      if (tint == null) return widget.child;
      if (widget.tintBevelWidth == 0) {
        return ColoredBox(color: tint, child: widget.child);
      }
      return CustomPaint(
        painter: _BeveledGlassTint(
          color: tint,
          radius: widget.borderRadius,
          bevelWidth: widget.tintBevelWidth,
        ),
        child: widget.child,
      );
    }

    if (!widget.refractive) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter.grouped(
          filter: _blurFilter,
          child: tintedChild(),
        ),
      );
    }
    // Register inset/size changes, including a dock moving above a keyboard.
    MediaQuery.maybeOf(context);
    // Measure the surface and viewport in the same completed layout pass.
    _measureBoundsAfterLayout();
    return LayoutBuilder(
      builder: (context, constraints) {
        final blur = _blurFilter;
        var filter = blur;
        final shader = _shader;
        final bounds = _surfaceBounds;
        final viewport = _viewportSize;
        final useShader = shader != null &&
            bounds != null &&
            !bounds.isEmpty &&
            viewport != null &&
            !viewport.isEmpty;
        if (useShader) {
          // Uniforms 0 and 1, and sampler 0, belong to ImageFilter.shader.
          shader
            ..setFloat(2, constraints.maxWidth)
            ..setFloat(3, widget.borderRadius)
            ..setFloat(4, widget.refraction)
            ..setFloat(5, widget.dispersion)
            ..setFloat(6, widget.bevelWidth)
            ..setFloat(7, bounds.left)
            ..setFloat(8, bounds.top)
            ..setFloat(9, bounds.width)
            ..setFloat(10, bounds.height)
            ..setFloat(11, viewport.width)
            ..setFloat(12, viewport.height);
          final lens = ui.ImageFilter.shader(shader);
          filter = widget.blurSigma == 0
              ? lens
              : ui.ImageFilter.compose(outer: lens, inner: blur);
        }
        return ClipRRect(
          key: _boundsKey,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: BackdropFilter(
            filter: filter,
            // Material color belongs to the foreground, so loading or changing
            // the optical shader can never remove its tint or label contrast.
            child: tintedChild(),
          ),
        );
      },
    );
  }
}

/// A clear rim exposes the optical filter while the lens face keeps its tint.
/// Nested fills avoid an extra blur, shader or offscreen mask for the coating.
class _BeveledGlassTint extends CustomPainter {
  const _BeveledGlassTint({
    required this.color,
    required this.radius,
    required this.bevelWidth,
  });

  final Color color;
  final double radius;
  final double bevelWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bevel = bevelWidth.clamp(0.0, size.shortestSide / 2);
    const steps = 12;
    var previousAlpha = 0.0;
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final targetAlpha = color.a * (.12 + .88 * t * t * (3 - 2 * t));
      final layerAlpha = (targetAlpha - previousAlpha) / (1 - previousAlpha);
      final inset = bevel * t;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(inset),
            Radius.circular((radius - inset).clamp(0.0, radius))),
        Paint()..color = color.withValues(alpha: layerAlpha),
      );
      previousAlpha = targetAlpha;
    }
  }

  @override
  bool shouldRepaint(_BeveledGlassTint oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.bevelWidth != bevelWidth;
}
