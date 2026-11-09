import 'dart:ui';
import 'package:flutter/material.dart';

Color mobileAccentText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF0AD7C)
        : const Color(0xFF9A471B);

/// Custom painter for liquid glass specular borders with directional light catch.
class LiquidGlassBorderPainter extends CustomPainter {
  LiquidGlassBorderPainter({
    required this.borderRadius,
    required this.borderGradient,
    this.borderWidth = 1.2,
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
  bool shouldRepaint(covariant LiquidGlassBorderPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.borderGradient != borderGradient ||
      oldDelegate.borderWidth != borderWidth;
}

/// Search stays visually compact while growing with the user's text size.
/// Engineered with authentic Liquid Glass aesthetic: translucent frosted fill,
/// directional specular border reflections, and soft ambient refraction glow.
class MobileSearchField extends StatefulWidget {
  const MobileSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  State<MobileSearchField> createState() => _MobileSearchFieldState();
}

class _MobileSearchFieldState extends State<MobileSearchField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onControllerChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  void _onControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(MobileSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fillGradient = isDark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 1.0],
            colors: [
              const Color(0xFF1E2B3E).withValues(alpha: 0.82),
              const Color(0xFF142032).withValues(alpha: 0.74),
              const Color(0xFF0F1826).withValues(alpha: 0.80),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 1.0],
            colors: [
              Colors.white.withValues(alpha: 0.85),
              const Color(0xFFFFF9F2).withValues(alpha: 0.68),
              Colors.white.withValues(alpha: 0.78),
            ],
          );

    final borderGradient = _isFocused
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.50, 1.0],
            colors: [
              Color(0xFFFF9E58),
              Color(0xFFDF762D),
              Color(0xFFBA4708),
            ],
          )
        : (isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.45, 0.85, 1.0],
                colors: [
                  Colors.white.withValues(alpha: 0.42),
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.08),
                  const Color(0xFFDF762D).withValues(alpha: 0.32),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.45, 0.85, 1.0],
                colors: [
                  Colors.white,
                  Colors.white.withValues(alpha: 0.70),
                  const Color(0xFFE2D9CF).withValues(alpha: 0.65),
                  const Color(0xFFDF762D).withValues(alpha: 0.38),
                ],
              ));

    const radius = 18.0;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 52),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.35)
                  : const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: (_isFocused
                      ? const Color(0xFFDF762D)
                      : const Color(0xFFFF9E58))
                  .withValues(
                      alpha: isDark
                          ? (_isFocused ? 0.25 : 0.08)
                          : (_isFocused ? 0.20 : 0.06)),
              blurRadius: _isFocused ? 14 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: CustomPaint(
              foregroundPainter: LiquidGlassBorderPainter(
                borderRadius: radius,
                borderGradient: borderGradient,
                borderWidth: _isFocused ? 1.5 : 1.2,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: fillGradient,
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w400,
                    ),
                    isDense: true,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: isDark
                          ? const Color(0xFFF0AD7C)
                          : const Color(0xFFDF762D),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 44, minHeight: 48),
                    suffixIcon: widget.controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            iconSize: 18,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              widget.controller.clear();
                              widget.onChanged('');
                            },
                          ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Matching Liquid Glass sort button with frosted blur and specular rim.
class LiquidGlassSortButton extends StatelessWidget {
  const LiquidGlassSortButton({
    super.key,
    required this.availableFirst,
    required this.onChanged,
  });

  final bool availableFirst;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final fillGradient = isDark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 1.0],
            colors: [
              const Color(0xFF1E2B3E).withValues(alpha: 0.82),
              const Color(0xFF142032).withValues(alpha: 0.74),
              const Color(0xFF0F1826).withValues(alpha: 0.80),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 1.0],
            colors: [
              Colors.white.withValues(alpha: 0.85),
              const Color(0xFFFFF9F2).withValues(alpha: 0.68),
              Colors.white.withValues(alpha: 0.78),
            ],
          );

    final borderGradient = isDark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 0.85, 1.0],
            colors: [
              Colors.white.withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.08),
              const Color(0xFFDF762D).withValues(alpha: 0.32),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.45, 0.85, 1.0],
            colors: [
              Colors.white,
              Colors.white.withValues(alpha: 0.70),
              const Color(0xFFE2D9CF).withValues(alpha: 0.65),
              const Color(0xFFDF762D).withValues(alpha: 0.38),
            ],
          );

    const radius = 18.0;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFDF762D).withValues(
              alpha: isDark ? 0.08 : 0.06,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: CustomPaint(
            foregroundPainter: LiquidGlassBorderPainter(
              borderRadius: radius,
              borderGradient: borderGradient,
              borderWidth: 1.2,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: fillGradient,
              ),
              child: PopupMenuButton<String>(
                tooltip: 'Sort equipment',
                icon: Icon(
                  Icons.tune_rounded,
                  size: 22,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                initialValue: availableFirst ? 'available' : 'name',
                onSelected: (value) => onChanged(value == 'available'),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 'available',
                    checked: availableFirst,
                    child: const Text('Available first'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'name',
                    checked: !availableFirst,
                    child: const Text('Name A–Z'),
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

class MobileFilterChip extends StatelessWidget {
  const MobileFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        selected ? mobileAccentText(context) : scheme.onSurfaceVariant;
    final leading = icon;

    final glassBg = selected
        ? (isDark
            ? const Color(0xFFDF762D).withValues(alpha: 0.18)
            : const Color(0xFFFFF3EB))
        : (isDark
            ? const Color(0xFF1E2D44).withValues(alpha: 0.7)
            : Colors.white.withValues(alpha: 0.85));

    final glassBorder = selected
        ? (isDark
            ? const Color(0xFFF0AD7C).withValues(alpha: 0.5)
            : const Color(0xFFDF762D).withValues(alpha: 0.4))
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFE2E8F0));

    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: leading == null
          ? null
          : Icon(
              leading,
              size: 16,
              color: selected
                  ? (isDark ? const Color(0xFFF0AD7C) : const Color(0xFFDF762D))
                  : foreground,
            ),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected
            ? (isDark ? const Color(0xFFF0AD7C) : const Color(0xFFDF762D))
            : foreground,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: glassBg,
      selectedColor: glassBg,
      side: BorderSide(color: glassBorder, width: 1.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      onSelected: onSelected,
    );
  }
}

class MobileCategoryChip extends StatelessWidget {
  const MobileCategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (selected) {
      // Liquid glass active pill with gradient glow and specular highlight
      return GestureDetector(
        onTap: onSelected,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFF8A3D),
                Color(0xFFDF762D),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDF762D).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Frosted glass inactive pill
    final glassBg = isDark
        ? const Color(0xFF1E2D44).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.85);
    final glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE2E8F0);

    return ChoiceChip(
      label: Text(label),
      selected: false,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      backgroundColor: glassBg,
      side: BorderSide(color: glassBorder, width: 1.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (_) => onSelected(),
    );
  }
}

