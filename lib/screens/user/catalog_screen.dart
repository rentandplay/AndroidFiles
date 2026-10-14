import '../../services/mobile_api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rent_play_wordmark.dart';
import '../auth/login_screen.dart';
import 'item_details_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../../widgets/notification_widgets.dart';
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
  bool _availableFirst = true;
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

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.initialCategory;
    _loadCatalog();
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

  Future<void> _loadCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = '';
    });
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
          _catalogError = error.toString();
          _catalogLoading = false;
        });
      }
    }
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
      if (_availableFirst) {
        final availability = (b.status.toLowerCase() == 'available' ? 1 : 0)
            .compareTo(a.status.toLowerCase() == 'available' ? 1 : 0);
        if (availability != 0) return availability;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
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
    return MobileFilterChip(
      key: ValueKey(id),
      selected: selected,
      icon: icon,
      label: label,
      onSelected: onSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final textScale = (MediaQuery.textScalerOf(context).scale(15) / 15)
        .clamp(1.0, double.infinity);
    final width = MediaQuery.sizeOf(context).width;
    final gridColumns = width >= 760
        ? 3
        : width < 350 && textScale > 1.2
            ? 1
            : 2;
    final isAdmin = _currentUserModel?.isStaff == true;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF192536) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const RentPlayWordmark(),
        actions: [
          if (user == null)
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.login),
              label: const Text('Login'),
            )
          else ...[
            const RentalNotificationBell(),
            if (isAdmin)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert, size: 22),
                tooltip: 'More Options',
                onSelected: (value) async {
                  if (value == 'admin') {
                    final navigator = Navigator.of(context);
                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => AdminDashboardScreen(
                          onSignedOut: () {
                            navigator.pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                              (route) => false,
                            );
                          },
                        ),
                      ),
                    );
                  } else if (value == 'logout') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged out successfully.')),
                    );
                    await authService.logout();
                    if (mounted) setState(() => _currentUserModel = null);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'admin',
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings_outlined,
                            size: 20, color: Color(0xFFF57C00)),
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
                        Icon(Icons.logout, size: 20, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Logout',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCatalog,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_catalogLoading)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(children: [
                  Expanded(
                      child: MobileSearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    hintText: 'Search equipment',
                  )),
                  const SizedBox(width: 8),
                  Material(
                    color: scheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: scheme.outline)),
                    child: SizedBox(
                        width: 48,
                        height: 48,
                        child: PopupMenuButton<String>(
                          tooltip: 'Sort equipment',
                          icon: Icon(Icons.sort_rounded,
                              size: 20, color: scheme.onSurfaceVariant),
                          initialValue: _availableFirst ? 'available' : 'name',
                          onSelected: (value) => setState(
                              () => _availableFirst = value == 'available'),
                          itemBuilder: (_) => [
                            CheckedPopupMenuItem(
                                value: 'available',
                                checked: _availableFirst,
                                child: const Text('Available first')),
                            CheckedPopupMenuItem(
                                value: 'name',
                                checked: !_availableFirst,
                                child: const Text('Name A–Z')),
                          ],
                        )),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                height: 48 + (textScale - 1) * 16,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = selectedCategory == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 9),
                      child: MobileCategoryChip(
                        label: category,
                        selected: isSelected,
                        onSelected: () =>
                            setState(() => selectedCategory = category),
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
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
            ),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: Text(
                  '${filteredItems.length} item${filteredItems.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            )),
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
                                    _savedOnly)) ...[
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridColumns,
                    mainAxisExtent: 110 + 160 * textScale,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildItemCard(filteredItems[index]),
                    childCount: filteredItems.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    final isSaved = _savedItemIds.contains(item.id);
    final scheme = Theme.of(context).colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusKey = item.status.toUpperCase();
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

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline),
      ),
      child: InkWell(
        onTap: () => _openItemDetails(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 110,
                  width: double.infinity,
                  color: isDark
                      ? AppTheme.darkSurfaceVariant
                      : const Color(0xFFF3F5F7),
                  child: item.buildImage(fit: BoxFit.contain, height: 110),
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
                            color: Theme.of(context)
                                .colorScheme
                                .surface
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
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: scheme.surface.withValues(alpha: .96),
                                  border: Border.all(
                                      color: statusColor.withValues(alpha: .2)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(statusLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: statusColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .2)),
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
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 40 *
                          (MediaQuery.textScalerOf(context).scale(13) / 13)
                              .clamp(1.0, double.infinity),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: mobileAccentText(context),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _openItemDetails(item),
                        child: Row(children: [
                          const Expanded(
                              child: Text('View details',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700))),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 16),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
