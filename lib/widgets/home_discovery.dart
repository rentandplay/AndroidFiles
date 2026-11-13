import 'premium_animations.dart';
import 'package:flutter/material.dart';

import '../models/item_model.dart';
import '../theme/app_theme.dart';
import '../utils/catalog_price.dart';
import 'liquid_glass.dart';

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
              for (var i = 0; i < categories.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _categoryChip(context, categories[i]),
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
                for (var i = 0; i < suggestions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 4),
                    child: _equipmentCard(context, suggestions[i]),
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
    final accent = _categoryColor(category);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumPressable(
      onTap: () => onCategorySelected(category),
      child: LiquidGlassContainer(
        borderRadius: 22,
        blurSigma: 10,
        glowColor: accent,
        padding: const EdgeInsets.fromLTRB(8, 7, 16, 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.28 : 0.18),
                accent.withValues(alpha: isDark ? 0.14 : 0.08),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.45 : 0.32),
              width: 1.0,
            ),
          ),
          child: Icon(_categoryIcon(category), color: accent, size: 18),
        ),
        const SizedBox(width: 9),
        Text(category,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.15,
                color: isDark ? Colors.white : const Color(0xFF1E293B))),
      ]),
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
    final width = (MediaQuery.sizeOf(context).width * .48).clamp(165.0, 210.0);
    return SizedBox(
      width: width,
      child: PremiumPressable(
        onTap: () => onItemSelected(item),
        child: LiquidGlassContainer(
          borderRadius: 22,
          blurSigma: 10,
          glowColor: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Container(
                  height: 116,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.88,
                      colors: [
                        accent.withValues(alpha: dark ? .26 : .16),
                        accent.withValues(alpha: dark ? .04 : .02),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
                  child: Center(
                    child: Hero(
                      tag: 'item-image-${item.id}',
                      child: item.buildImage(fit: BoxFit.contain, height: 96),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 35,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: dark ? 0.08 : 0.45),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: (dark ? const Color(0xFF141D2C) : Colors.white)
                                .withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.34),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            item.category.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ),
                      if (item.isPopular) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF8A3D), Color(0xFFDF762D)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.local_fire_department_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: textScaler.scale(14) * 1.25 * 2),
                    child: Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            height: 1.25,
                            letterSpacing: -0.2,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: (dark
                              ? const Color(0xFF1E2838)
                              : const Color(0xFFFFF7ED))
                          .withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: const Color(0xFFDF762D).withValues(alpha: 0.30),
                        width: 1.0,
                      ),
                    ),
                    child: Tooltip(
                      message: item.rateText.isEmpty ? rate : item.rateText,
                      child: Text(rate,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              height: 1.25,
                              color: Color(0xFFDF762D),
                              fontFeatures: [FontFeature.tabularFigures()],
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: available
                            ? const Color(0xFF10B981)
                            : scheme.onSurfaceVariant,
                        boxShadow: available
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.50),
                                  blurRadius: 5,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(available ? 'Available' : 'Unavailable',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: available
                                    ? dark
                                        ? const Color(0xFF89D5B8)
                                        : const Color(0xFF047857)
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700))),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFDF762D)
                            .withValues(alpha: dark ? 0.22 : 0.12),
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          size: 13, color: Color(0xFFDF762D)),
                    ),
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
        child: GlassCard(
          borderRadius: 18,
          padding: const EdgeInsets.all(16),
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
      child: LiquidGlassContainer(
        borderRadius: 24,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDF762D).withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.help_outline_rounded,
                    size: 16, color: Color(0xFFDF762D)),
              ),
              const SizedBox(width: 8),
              Text('How it works',
                  style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (dark ? const Color(0xFF1E2838) : Colors.white)
                          .withValues(alpha: dark ? 0.72 : 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.10)
                            : const Color(0xFFE8E2D9),
                      ),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF8A3D),
                                    Color(0xFFDF762D)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(steps[i].$1,
                                  color: Colors.white, size: 18)),
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
                        ]),
                  )),
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
