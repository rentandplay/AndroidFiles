import 'package:flutter/material.dart';

Color mobileAccentText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF0AD7C)
        : const Color(0xFF9A471B);

/// Search stays visually compact while growing with the user's text size.
/// Styled with iOS 27 Liquid Glass aesthetic: translucent frosted fill and specular borders.
class MobileSearchField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final glassFill = isDark
        ? const Color(0xFF192536).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.90);

    final glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFE2E8F0);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 52),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
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
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: 14,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              fontWeight: FontWeight.w400,
            ),
            isDense: true,
            filled: true,
            fillColor: glassFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 20,
              color: isDark ? const Color(0xFFF0AD7C) : const Color(0xFFDF762D),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 48),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    iconSize: 18,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: glassBorder, width: 1.1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: glassBorder, width: 1.1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFFF57C00) : const Color(0xFFDF762D),
                width: 1.5,
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
    final leading = icon ?? (selected ? Icons.check_rounded : null);

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

