import '../../widgets/app_glass_backdrop.dart';
import '../../widgets/customer_home_backdrop.dart';
import '../../widgets/brand_hero_header.dart';
import 'package:flutter/services.dart';
import '../../widgets/premium_animations.dart';
import '../../widgets/glass_app_bar.dart';
import 'dart:async';
import '../../services/mobile_api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/rent_play_wordmark.dart';
import '../auth/login_screen.dart';
import 'item_details_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../../widgets/mobile_controls.dart';
import '../../utils/catalog_price.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.initialCategory = 'All', this.api});
  final String initialCategory;
  final MobileApiService? api;

  @override
  State<CatalogScreen> createState() => CatalogScreenState();
}

class CatalogScreenState extends State<CatalogScreen> {
  String selectedCategory = 'All';
  UserModel? _currentUserModel;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _availableOnly = false;
  bool _savedOnly = false;
  String _sortOption = 'available';
  final Set<String> _savedItemIds = {};
  String? _savedOwnerId;
  List<ItemModel> catalogItems = [];
  bool _catalogLoading = true;
  String _catalogError = "";

  List<String> get categories {
    final values = catalogItems.map((item) => item.category).toSet().toList()
      ..sort();
    return ['All', ...values];
  }

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.initialCategory;
    _loadCatalog();
    final api = widget.api ?? MobileApiService.instance;
    _eventSubscription = api.watchRentalEvents().listen((event) {
      if (!mounted) return;
      final type = (event['event'] ?? '').toString();
      if (type == 'ready' || type.endsWith('.changed')) {
        _loadCatalog(quiet: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<AuthService>().currentUser?.uid;
    if (_savedOwnerId == userId) return;
    _savedOwnerId = userId;
    _savedItemIds.clear();
    _savedOnly = false;
    _currentUserModel = null;
    if (userId != null) _loadCurrentUserModel();
  }

  bool get _canSave => _savedOwnerId != null;

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserModel() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid;
      if (userId == null) return;
      final userModel = await authService.getCurrentUserModel();
      if (mounted && _savedOwnerId == userId) {
        setState(() => _currentUserModel = userModel);
      }
    } catch (_) {
      // Keep customer-facing navigation available if the profile is unavailable.
    }
  }

  Future<void> _loadCatalog({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _catalogLoading = true;
        _catalogError = '';
      });
    }
    try {
      final records = await (widget.api ?? MobileApiService.instance).catalog();
      if (mounted) {
        setState(() {
          catalogItems = records
              .map((row) => ItemModel.fromMap(row, id: row['id'].toString()))
              .toList();
          _catalogLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (!quiet || catalogItems.isEmpty) _catalogError = error.toString();
          _catalogLoading = false;
        });
      }
    }
  }

  String _sortLabel(String sort) {
    switch (sort) {
      case 'popular':
        return 'Most Popular';
      case 'price_asc':
        return 'Price: Low to High';
      case 'price_desc':
        return 'Price: High to Low';
      case 'name_asc':
        return 'Name: A–Z';
      case 'name_desc':
        return 'Name: Z–A';
      case 'available':
      default:
        return 'Available first';
    }
  }

  double _getItemPrice(ItemModel item) {
    final options = item.rateOptions.where((option) {
      final amount = option['amount'];
      return amount is num && amount.isFinite && amount >= 0;
    }).toList();
    if (options.isNotEmpty) {
      options.sort((a, b) => (a['amount'] as num).compareTo(b['amount'] as num));
      return (options.first['amount'] as num).toDouble();
    }
    if (item.rateHourly > 0) {
      return item.rateHourly;
    }
    if (item.salePrice != null && item.salePrice! > 0) {
      return item.salePrice!;
    }
    final match = RegExp(r'₱\s*([\d,]+(?:\.\d+)?)').firstMatch(item.rateText);
    if (match != null) {
      final parsed = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
    return 0.0;
  }

  List<ItemModel> get filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    final items = catalogItems.where((item) {
      if (selectedCategory != 'All' && item.category != selectedCategory) {
        return false;
      }
      if (_availableOnly && item.status.toLowerCase() != 'available') {
        return false;
      }
      if (_canSave && _savedOnly && !_savedItemIds.contains(item.id)) {
        return false;
      }
      if (query.isEmpty) return true;
      return '${item.name} ${item.category} ${item.description} ${item.rateText}'
          .toLowerCase()
          .contains(query);
    }).toList();

    items.sort((a, b) {
      final aAvail = a.status.toLowerCase() == 'available' ? 1 : 0;
      final bAvail = b.status.toLowerCase() == 'available' ? 1 : 0;

      switch (_sortOption) {
        case 'available':
          final availability = bAvail.compareTo(aAvail);
          if (availability != 0) return availability;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());

        case 'popular':
          final aPop = a.isPopular ? 1 : 0;
          final bPop = b.isPopular ? 1 : 0;
          final popComp = bPop.compareTo(aPop);
          if (popComp != 0) return popComp;
          final availability = bAvail.compareTo(aAvail);
          if (availability != 0) return availability;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());

        case 'price_asc':
          final pA = _getItemPrice(a);
          final pB = _getItemPrice(b);
          final pComp = pA.compareTo(pB);
          if (pComp != 0) return pComp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());

        case 'price_desc':
          final pA = _getItemPrice(a);
          final pB = _getItemPrice(b);
          final pComp = pB.compareTo(pA);
          if (pComp != 0) return pComp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());

        case 'name_desc':
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());

        case 'name_asc':
        default:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });

    return items;
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      selectedCategory = 'All';
      _availableOnly = false;
      _savedOnly = false;
      _sortOption = 'available';
    });
  }

  /// Opens a category from Home without retaining an unrelated search/filter.
  void selectCategory(String category) {
    _searchController.clear();
    setState(() {
      selectedCategory = category;
      _searchQuery = '';
      _availableOnly = false;
      _savedOnly = false;
    });
  }

  void _openItemDetails(ItemModel item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item)),
    );
  }

  void _toggleSaved(ItemModel item) {
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId == null || userId != _savedOwnerId) return;
    setState(() {
      if (!_savedItemIds.remove(item.id)) _savedItemIds.add(item.id);
    });
  }

  Widget _filterChip({
    required String id,
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return PremiumPressable(
      onTap: () => onSelected(!selected),
      child: MobileFilterChip(
        key: ValueKey(id),
        selected: selected,
        icon: icon,
        label: label,
        onSelected: onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textScale = (MediaQuery.textScalerOf(context).scale(15) / 15)
        .clamp(1.0, double.infinity);
    final width = MediaQuery.sizeOf(context).width;
    final gridColumns = width >= 760
        ? 3
        : width < 350 && textScale > 1.2
            ? 1
            : 2;
    final isAdmin = _currentUserModel?.isStaff == true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0B1320) : const Color(0xFFF6F8FC),
        body: AppGlassBackdrop(
            child: RefreshIndicator(
          edgeOffset: MediaQuery.of(context).padding.top + 50,
          onRefresh: _loadCatalog,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 1. Signature Midnight Navy & Glowing Orange Swoosh Hero Header with Wave Bottom
              SliverToBoxAdapter(
                child: ClipPath(
                  clipper: const BrowseHeroBottomWaveClipper(),
                  child: CustomerHomeHeroBackground(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const RentPlayWordmark(isLightOnDark: true),
                            if (user == null)
                              HeroLoginButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen()),
                                ),
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const RentalNotificationBellPod(
                                    podBg: Color(0x28FFFFFF),
                                    podBorder: Color(0x40FFFFFF),
                                    iconColor: Colors.white,
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 6),
                                    HeaderActionPod(
                                      podBg: Colors.white
                                          .withValues(alpha: 0.16),
                                      podBorder: Colors.white
                                          .withValues(alpha: 0.25),
                                      iconColor: Colors.white,
                                      child: PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.more_vert,
                                            size: 20),
                                        tooltip: 'More Options',
                                        onSelected: (value) async {
                                          if (value == 'admin') {
                                            final navigator =
                                                Navigator.of(context);
                                            navigator.push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AdminDashboardScreen(
                                                  onSignedOut: () {
                                                    navigator
                                                        .pushAndRemoveUntil(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const LoginScreen(),
                                                      ),
                                                      (route) => false,
                                                    );
                                                  },
                                                ),
                                              ),
                                            );
                                          } else if (value == 'logout') {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Logged out successfully.')),
                                            );
                                            await authService.logout();
                                            if (mounted) {
                                              setState(() =>
                                                  _currentUserModel = null);
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'admin',
                                            child: Row(
                                              children: [
                                                Icon(
                                                    Icons
                                                        .admin_panel_settings_outlined,
                                                    size: 20,
                                                    color:
                                                        Color(0xFFF57C00)),
                                                SizedBox(width: 10),
                                                Text('Staff Dashboard'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: 'logout',
                                            child: Row(
                                              children: [
                                                Icon(Icons.logout,
                                                    size: 20,
                                                    color: Colors.red),
                                                SizedBox(width: 10),
                                                Text('Logout',
                                                    style: TextStyle(
                                                        color: Colors.red,
                                                        fontWeight:
                                                            FontWeight
                                                                .bold)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Search Controls, Category Chips & Filters below the wave header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Liquid Glass Search bar + matching Sort/Tune button
                      Row(
                        children: [
                          Expanded(
                            child: MobileSearchField(
                              controller: _searchController,
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                              hintText: 'Search equipment',
                            ),
                          ),
                          const SizedBox(width: 10),
                          LiquidGlassSortButton(
                            selectedSort: _sortOption,
                            onChanged: (value) =>
                                setState(() => _sortOption = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Horizontal Category Chips row spanning full screen width
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (final category in categories)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: BrowseCategoryChip(
                                  label: category,
                                  isSelected: selectedCategory == category,
                                  onSelected: () => setState(
                                      () => selectedCategory = category),
                                ),
                              ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(
                              id: 'catalog-available-filter',
                              selected: _availableOnly,
                              icon: _availableOnly
                                  ? Icons.check_circle_rounded
                                  : Icons.check_circle_outline,
                              label: 'Available only',
                              onSelected: (selected) =>
                                  setState(() => _availableOnly = selected),
                            ),
                            if (user != null) ...[
                              const SizedBox(width: 8),
                              _filterChip(
                                id: 'catalog-saved-filter',
                                selected: _savedOnly,
                                icon: _savedOnly
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                label: 'Saved (${_savedItemIds.length})',
                                onSelected: (selected) =>
                                    setState(() => _savedOnly = selected),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Row(
                          children: [
                            Text(
                              '${filteredItems.length} ${filteredItems.length == 1 ? 'item' : 'items'}',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (_sortOption != 'available') ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => setState(
                                    () => _sortOption = 'available'),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDF762D).withValues(
                                        alpha: isDark ? 0.2 : 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFDF762D)
                                          .withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _sortLabel(_sortOption),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFDF762D),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.close_rounded,
                                        size: 13,
                                        color: Color(0xFFDF762D),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_catalogError.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text(_catalogError),
                        TextButton(
                          onPressed: _loadCatalog,
                          child: const Text('Retry catalog'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (filteredItems.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: _catalogLoading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.toys_outlined,
                                size: 42,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _catalogError.isNotEmpty
                                    ? 'Catalog unavailable'
                                    : _searchQuery.isNotEmpty ||
                                            _availableOnly ||
                                            _savedOnly
                                        ? 'No matching equipment'
                                        : 'No items in this category yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (_catalogError.isNotEmpty &&
                                  !_catalogLoading) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'We could not load equipment right now. Please try again later.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: _loadCatalog,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try again'),
                                ),
                              ] else if (!_catalogLoading &&
                                  (_searchQuery.isNotEmpty ||
                                      selectedCategory != 'All' ||
                                      _availableOnly ||
                                      _savedOnly ||
                                      _sortOption != 'available')) ...[
                                const SizedBox(height: 6),
                                TextButton(
                                  onPressed: _clearFilters,
                                  child: const Text('Clear search and filters'),
                                ),
                              ],
                            ],
                          ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridColumns,
                      mainAxisExtent: 110 + 165 * textScale,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => StaggeredSlideFade(
                        index: index,
                        child: _buildItemCard(filteredItems[index]),
                      ),
                      childCount: filteredItems.length,
                    ),
                  ),
                ),
            ],
          ),
        )),
      ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    final isSaved = _savedItemIds.contains(item.id);
    final textScaler = MediaQuery.textScalerOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final statusKey = item.status.toUpperCase();
    final isAvailable = statusKey == 'AVAILABLE' && item.availableQuantity > 0;
    final statusColor = switch (statusKey) {
      'AVAILABLE' => isDark ? const Color(0xFF89D5B8) : const Color(0xFF216F56),
      'RENTED' || 'RESERVED_PENDING' => mobileAccentText(context),
      _ => scheme.onSurfaceVariant,
    };
    final statusLabel = item.totalQuantity > 1
        ? '${item.availableQuantity}/${item.totalQuantity} available'
        : switch (statusKey) {
            'AVAILABLE' => 'Available',
            'RESERVED_PENDING' => 'On hold',
            'RENTED' => 'Rented',
            'UNDER_MAINTENANCE' => 'Maintenance',
            'UNDER_INSPECTION' => 'Inspection',
            _ => 'Unavailable',
          };

    return HoverLiftCard(
      onTap: () => _openItemDetails(item),
      builder: (context, isHovered) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 112,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.85,
                      colors: [
                        (isDark
                                ? const Color(0xFF233248)
                                : const Color(0xFFF6EFE6))
                            .withValues(alpha: isDark ? 0.55 : 0.70),
                        (isDark
                                ? const Color(0xFF151F2E)
                                : const Color(0xFFFCF9F5))
                            .withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Center(
                    child: AnimatedScale(
                      scale: isHovered ? 1.06 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Hero(
                        tag: 'item-image-${item.id}',
                        child: Opacity(
                          opacity: isAvailable ? 1.0 : 0.65,
                          child: item.buildImage(fit: BoxFit.contain, height: 100),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 40,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white
                                .withValues(alpha: isDark ? 0.06 : 0.35),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_canSave) ...[
                          Material(
                            color: (isDark
                                    ? const Color(0xFF192536)
                                    : Colors.white)
                                .withValues(alpha: .94),
                            shape: const CircleBorder(),
                            child: IconButton(
                              key: ValueKey('catalog-save-${item.id}'),
                              tooltip:
                                  isSaved ? 'Remove from saved' : 'Save item',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _toggleSaved(item),
                              icon: Icon(
                                  isSaved
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: isSaved
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                  size: 20),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (!_canSave) const Spacer(),
                        Flexible(
                            flex: 4,
                            child: Tooltip(
                              message: statusLabel,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (isDark
                                          ? const Color(0xFF131D2D)
                                          : Colors.white)
                                      .withValues(alpha: .96),
                                  border: Border.all(
                                      color: statusColor.withValues(alpha: .38),
                                      width: 1.0),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: statusColor,
                                        boxShadow: statusKey == 'AVAILABLE'
                                            ? [
                                                BoxShadow(
                                                  color: statusColor.withValues(
                                                      alpha: 0.55),
                                                  blurRadius: 5,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        statusLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: .2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ]),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: textScaler.scale(14) * 1.25 * 2),
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        )),
                    const SizedBox(height: 4),
                    Text(
                      item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message: item.rateText,
                      child: Text(
                        catalogPriceLabel(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mobileAccentText(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 38 *
                          (MediaQuery.textScalerOf(context).scale(13) / 13)
                              .clamp(1.0, double.infinity),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: isHovered
                              ? const Color(0xFFE46618)
                              : (isDark
                                  ? const Color(0xFF1E2838)
                                  : const Color(0xFFFFF4EB)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFDF762D)
                                .withValues(alpha: isHovered ? 0.80 : 0.35),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFDF762D)
                                  .withValues(alpha: isHovered ? 0.28 : 0.10),
                              blurRadius: isHovered ? 8 : 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                'View details',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isHovered
                                      ? Colors.white
                                      : const Color(0xFFDF762D),
                                ),
                              ),
                            ),
                            AnimatedSlide(
                              offset: Offset(isHovered ? 0.22 : 0.0, 0.0),
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: isHovered
                                    ? Colors.white
                                    : const Color(0xFFDF762D),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
