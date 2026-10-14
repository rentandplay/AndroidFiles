import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../theme/app_theme.dart';
import '../utils/catalog_price.dart';
import 'mobile_controls.dart';

/// Discovery content uses the live catalog, including its prices and stock.
class HomeDiscovery extends StatelessWidget {
  const HomeDiscovery({
    super.key,
    required this.items,
    required this.featuredIds,
    required this.loading,
    required this.hasError,
    required this.onBrowse,
    required this.onCategorySelected,
    required this.onItemSelected,
    required this.onRetry,
  });

  final List<ItemModel> items;
  final Set<String> featuredIds;
  final bool loading, hasError;
  final VoidCallback onBrowse, onRetry;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<ItemModel> onItemSelected;

  List<String> get _categories {
    final values = items
        .map((item) => item.category.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    const order = ['Sports', 'Board Games', 'Cards', 'Tech Rentals'];
    values.sort((a, b) {
      final ai = order.indexOf(a), bi = order.indexOf(b);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.compareTo(b);
    });
    return values;
  }

  List<ItemModel> get _suggestions {
    final remaining =
        items.where((item) => !featuredIds.contains(item.id)).toList();
    remaining.sort((a, b) {
      final available = _isAvailable(b).compareTo(_isAvailable(a));
      return available != 0 ? available : a.name.compareTo(b.name);
    });
    // Give different activities a place in the preview before repeating one.
    final seen = <String>{};
    final firstInCategory = <ItemModel>[];
    final others = <ItemModel>[];
    for (final item in remaining) {
      (seen.add(item.category) ? firstInCategory : others).add(item);
    }
    return [...firstInCategory, ...others].take(6).toList();
  }

  static int _isAvailable(ItemModel item) =>
      item.status.toLowerCase() == 'available' && item.availableQuantity > 0
          ? 1
          : 0;

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final suggestions = _suggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (categories.isNotEmpty) ...[
          _heading(context, 'Browse by category', action: 'View all'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _categoryChip(context, category),
                ),
            ]),
          ),
          const SizedBox(height: 18),
        ],
        if (suggestions.isNotEmpty) ...[
          _heading(context, 'More to explore', action: 'See all'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 4),
                    child: _equipmentCard(context, item),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ] else if (items.isEmpty) ...[
          _catalogNotice(context),
          const SizedBox(height: 18),
        ],
        _rentalGuide(context),
      ],
    );
  }

  Widget _heading(BuildContext context, String title, {String? action}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 6),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, letterSpacing: -.25)),
          ),
          if (action != null)
            TextButton(
              onPressed: onBrowse,
              child: Text(action,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      );

  Widget _categoryChip(BuildContext context, String category) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _categoryColor(category);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onCategorySelected(category),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 8, 13, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(_categoryIcon(category), color: accent, size: 18),
            ),
            const SizedBox(width: 8),
            Text(category,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _equipmentCard(BuildContext context, ItemModel item) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final available = _isAvailable(item) == 1;
    final accent = _categoryColor(item.category);
    final rate = catalogPriceLabel(item);
    final textScaler = MediaQuery.textScalerOf(context);
    final width = (MediaQuery.sizeOf(context).width * .44).clamp(150.0, 200.0);
    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onItemSelected(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: accent.withValues(alpha: dark ? .16 : .06),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: item.buildImage(fit: BoxFit.contain, height: 100),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          minHeight: textScaler.scale(14) * 1.25 * 2),
                      child: Text(item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: textScaler.scale(11) * 1.3 * 2),
                        child: Tooltip(
                          message: item.rateText.isEmpty ? rate : item.rateText,
                          child: Text(rate,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  height: 1.3,
                                  color: mobileAccentText(context),
                                  fontWeight: FontWeight.w700)),
                        )),
                    const SizedBox(height: 9),
                    Row(children: [
                      Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: available
                                  ? const Color(0xFF27876B)
                                  : scheme.onSurfaceVariant)),
                      const SizedBox(width: 5),
                      Expanded(
                          child: Text(available ? 'Available' : 'Unavailable',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: available
                                      ? dark
                                          ? const Color(0xFF89D5B8)
                                          : const Color(0xFF216F56)
                                      : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600))),
                      Icon(Icons.arrow_forward_rounded,
                          size: 14, color: scheme.onSurfaceVariant),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catalogNotice(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(children: [
            Icon(
                loading
                    ? Icons.storefront_outlined
                    : Icons.inventory_2_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    loading
                        ? 'Finding your next game…'
                        : hasError
                            ? 'Equipment could not load. Try again.'
                            : 'New equipment will appear here when available.',
                    style: const TextStyle(fontSize: 12, height: 1.4))),
            if (hasError && !loading)
              IconButton(
                  onPressed: onRetry,
                  tooltip: 'Retry equipment',
                  icon: const Icon(Icons.refresh_rounded)),
          ]),
        ),
      );

  Widget _rentalGuide(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const steps = [
      (Icons.search_rounded, 'Choose', 'Find your gear'),
      (Icons.receipt_long_outlined, 'Request', 'Get staff approval'),
      (Icons.shopping_bag_outlined, 'Play', 'Pick up or get delivery'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: dark ? .12 : .06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.primary.withValues(alpha: .12)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How it works',
              style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(11)),
                        child:
                            Icon(steps[i].$1, color: scheme.primary, size: 19)),
                    const SizedBox(height: 8),
                    Text('${i + 1}. ${steps[i].$2}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(steps[i].$3,
                        style: TextStyle(
                            fontSize: 10,
                            height: 1.4,
                            color: scheme.onSurfaceVariant)),
                  ])),
            ],
          ]),
          const SizedBox(height: 14),
          Divider(height: 1, color: scheme.primary.withValues(alpha: .12)),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.badge_outlined, color: scheme.primary, size: 16),
            const SizedBox(width: 7),
            Expanded(
                child: Text('Bring a valid ID and your rental QR code.',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: scheme.onSurfaceVariant))),
          ]),
        ]),
      ),
    );
  }

  static IconData _categoryIcon(String category) => switch (category) {
        'Sports' => Icons.sports_basketball_outlined,
        'Board Games' => Icons.extension_outlined,
        'Cards' => Icons.style_outlined,
        'Tech Rentals' => Icons.sports_esports_outlined,
        _ => Icons.category_outlined,
      };

  static Color _categoryColor(String category) => switch (category) {
        'Board Games' => const Color(0xFF27876B),
        'Cards' => const Color(0xFF8062B5),
        'Tech Rentals' => const Color(0xFF4678B3),
        _ => AppTheme.brandOrange,
      };
}
