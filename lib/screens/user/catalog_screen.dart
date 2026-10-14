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
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;
    return FilterChip(
      key: ValueKey(id),
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 18, color: foreground),
      label: Text(label),
      labelStyle: TextStyle(
          color: foreground, fontSize: 12, fontWeight: FontWeight.w600),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: .1),
      side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: .35)
              : scheme.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onSelected: onSelected,
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search equipment or category',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = selectedCategory == category;
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Padding(
                      padding: const EdgeInsets.only(right: 9),
                      child: ChoiceChip(
                        label: Text(category),
                        avatar: isSelected
                            ? const Icon(Icons.check_rounded, size: 17)
                            : null,
                        selected: isSelected,
                        selectedColor: AppTheme.brandOrange,
                        backgroundColor:
                            isDark ? AppTheme.darkSurface : Colors.white,
                        side: BorderSide(
                          color: isDark
                              ? AppTheme.darkBorder
                              : const Color(0xFFE2E8F0),
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? AppTheme.darkTextPrimary
                                  : AppTheme.lightTextPrimary),
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => selectedCategory = category);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 12, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${filteredItems.length} item${filteredItems.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _availableFirst = !_availableFirst),
                      icon: const Icon(Icons.sort_rounded, size: 18),
                      label: Text(
                          _availableFirst ? 'Available first' : 'Name A–Z'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
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
                    mainAxisExtent:
                        120 + (gridColumns == 1 ? 150 : 160) * textScale,
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

    final statusKey = item.status.toUpperCase();
    final statusColor = switch (statusKey) {
      'AVAILABLE' => Colors.green,
      'RENTED' || 'RESERVED_PENDING' => Colors.orange,
      _ => Colors.red,
    };
    final statusLabel = item.totalQuantity > 1
        ? '${item.availableQuantity}/${item.totalQuantity} AVAILABLE'
        : switch (statusKey) {
            'AVAILABLE' => 'AVAILABLE',
            'RESERVED_PENDING' => 'ON HOLD',
            'RENTED' => 'RENTED',
            'UNAVAILABLE' || '' => 'UNAVAILABLE',
            _ => statusKey.replaceAll('_', ' '),
          };
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isDark ? 0 : 2,
      shadowColor: const Color(0x1A0F172A),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? AppTheme.darkBorder : const Color(0xFFE8ECF1),
        ),
      ),
      child: InkWell(
        onTap: () => _openItemDetails(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  color: isDark
                      ? AppTheme.darkSurfaceVariant
                      : const Color(0xFFF3F5F7),
                  child: item.buildImage(fit: BoxFit.contain, height: 120),
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
                                  color: statusColor.withValues(alpha: .92),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(statusLabel,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
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
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: item.rateText,
                      child: Text(
                        item.rateText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 40 *
                          (MediaQuery.textScalerOf(context).scale(13) / 13)
                              .clamp(1.0, double.infinity),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandOrangeLight,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _openItemDetails(item),
                        child: Text(
                          'View details',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
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
