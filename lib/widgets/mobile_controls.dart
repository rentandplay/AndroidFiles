import 'package:flutter/material.dart';

Color mobileAccentText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF0AD7C)
        : const Color(0xFF9A471B);

/// Search stays visually compact while growing with the user's text size.
class MobileSearchField extends StatelessWidget {
  const MobileSearchField(
      {super.key,
      required this.controller,
      required this.onChanged,
      required this.hintText});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        style: TextStyle(fontSize: 14, height: 1.3, color: scheme.onSurface),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: scheme.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: scheme.onSurfaceVariant),
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
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outline)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 1.2)),
        ),
      ),
    );
  }
}

class MobileFilterChip extends StatelessWidget {
  const MobileFilterChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onSelected,
      this.icon});

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? mobileAccentText(context) : scheme.onSurfaceVariant;
    final leading = icon ?? (selected ? Icons.check_rounded : null);
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar:
          leading == null ? null : Icon(leading, size: 16, color: foreground),
      label: Text(label),
      labelStyle: TextStyle(
          color: foreground, fontSize: 12, fontWeight: FontWeight.w600),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: .09),
      side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: .25)
              : scheme.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      onSelected: onSelected,
    );
  }
}

class MobileCategoryChip extends StatelessWidget {
  const MobileCategoryChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? mobileAccentText(context) : scheme.onSurfaceVariant;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      avatar: selected
          ? Icon(Icons.check_rounded, size: 16, color: foreground)
          : null,
      showCheckmark: false,
      labelStyle: TextStyle(
          color: foreground, fontSize: 12, fontWeight: FontWeight.w600),
      labelPadding: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: .09),
      side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: .25)
              : scheme.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (_) => onSelected(),
    );
  }
}
