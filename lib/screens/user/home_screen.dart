import '../../widgets/glass_app_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/item_model.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/home_discovery.dart';
import '../../utils/catalog_price.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rent_play_wordmark.dart';
import '../../widgets/rental_ui.dart';
import '../auth/login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onBrowse,
    required this.onViewRentals,
    required this.onItemSelected,
    this.onBrowseCategory,
    this.api,
  });

  final VoidCallback onBrowse;
  final VoidCallback onViewRentals;
  final ValueChanged<ItemModel> onItemSelected;
  final ValueChanged<String>? onBrowseCategory;
  final MobileApiService? api;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final PageController _carouselController =
      PageController(viewportFraction: .92);
  List<ItemModel> _catalogItems = [];
  List<ItemModel> _featuredItems = [];
  List<RentalModel> _rentals = [];
  bool _loading = true;
  String _rentalError = '';
  String _catalogError = '';
  int _carouselIndex = 0;

  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _loadHome();
    _eventSubscription = _api.watchRentalEvents().listen((event) {
      if (!mounted) return;
      final type = (event['event'] ?? '').toString();
      if (type == 'ready' || type.endsWith('.changed')) {
        _loadHome(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _loadHome({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    final isSignedIn =
        Provider.of<AuthService>(context, listen: false).currentUser != null;

    List<ItemModel> catalogItems = [];
    List<ItemModel> items = [];
    List<RentalModel> rentals = [];
    var rentalError = '';
    var catalogError = '';

    try {
      final records = await _api.catalog();
      catalogItems = records
          .map((row) => ItemModel.fromMap(row, id: row['id'].toString()))
          .toList();
      final available = catalogItems
          .where((item) => item.status.toLowerCase() == 'available')
          .toList();
      final featureCount = (available.length ~/ 2).clamp(1, 3).toInt();
      items = available.take(featureCount).toList();
    } catch (error) {
      catalogError = '$error';
      // Keep the rental summary usable if the featured catalog cannot load.
    }

    if (isSignedIn) {
      try {
        rentals = await _api.listRentals();
      } catch (error) {
        rentalError = '$error';
      }
    }

    if (!mounted) return;
    setState(() {
      _catalogItems = catalogItems;
      _featuredItems = items;
      _rentals = rentals;
      _rentalError = rentalError;
      _catalogError = catalogError;
      _loading = false;
      if (_carouselIndex >= items.length) _carouselIndex = 0;
    });
  }

  Future<void> refresh() => _loadHome();

  List<RentalModel> get _activeRentals =>
      _rentals.where((rental) => rental.isActive).toList()
        ..sort((a, b) {
          final aHasDueDate = a.dueDate.millisecondsSinceEpoch > 0;
          final bHasDueDate = b.dueDate.millisecondsSinceEpoch > 0;
          if (aHasDueDate != bHasDueDate) return aHasDueDate ? -1 : 1;
          return a.dueDate.compareTo(b.dueDate);
        });

  List<RentalModel> get _currentRequests => _rentals
      .where((rental) =>
          rental.isOpen && !rental.isActive && !_hasExpiredHold(rental))
      .toList()
    ..sort((a, b) => b.startDate.compareTo(a.startDate));

  bool _hasExpiredHold(RentalModel rental) =>
      rental.canCancel &&
      rental.holdExpiresAt != null &&
      DateTime.now().isAfter(rental.holdExpiresAt!);

  String _date(DateTime value) =>
      DateFormat('MMM d, h:mm a').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final scheme = Theme.of(context).colorScheme;
    final activeRentals = _activeRentals;
    final currentRequests = _currentRequests;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1320) : const Color(0xFFF6F8FC),
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        loading: _loading,
        title: const RentPlayWordmark(),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Search equipment',
            icon: const Icon(Icons.search_rounded),
            onPressed: widget.onBrowse,
          ),
          if (user == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFDF762D)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDF762D).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('Sign in',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            )
          else
            const RentalNotificationBellPod(),
        ],
      ),
      body: LiquidAmbientBackdrop(
        child: RefreshIndicator(
          edgeOffset: topPadding,
          onRefresh: _loadHome,
          child: ListView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(0, topPadding + 8, 0, 28),
            children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName?.trim().isNotEmpty == true
                              ? 'Welcome back, ${user!.displayName!.trim().split(' ').first} 👋'
                              : 'Welcome to Rent & Play! 👋',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                letterSpacing: -.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find something fun for your next day out.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  _buildCarousel(context),
                  if (_featuredItems.length > 1) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _featuredItems.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: index == _carouselIndex ? 18 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: index == _carouselIndex
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (user != null &&
                      _rentalError.isEmpty &&
                      activeRentals.isNotEmpty)
                    _buildRentalListSection(
                      context,
                      title: 'Active rentals',
                      subtitle: 'Equipment currently in your care.',
                      rentals: activeRentals,
                    ),
                  if (user == null)
                    _buildSignInCard(context)
                  else if (_rentalError.isNotEmpty)
                    _buildRentalError(context)
                  else if (_loading && _rentals.isEmpty)
                    _buildRentalsLoadingCard(context)
                  else if (currentRequests.isNotEmpty)
                    _buildRentalListSection(
                      context,
                      title: 'Rental updates',
                      subtitle: 'Requests, handoffs, and returns in progress.',
                      rentals: currentRequests,
                    )
                  else if (activeRentals.isEmpty)
                    _buildNoRentalsCard(context),
                  const SizedBox(height: 8),
                  HomeDiscovery(
                    items: _catalogItems,
                    featuredIds: _featuredItems.map((item) => item.id).toSet(),
                    loading: _loading,
                    hasError: _catalogError.isNotEmpty,
                    onBrowse: widget.onBrowse,
                    onCategorySelected:
                        widget.onBrowseCategory ?? (_) => widget.onBrowse(),
                    onItemSelected: widget.onItemSelected,
                    onRetry: _loadHome,
                  ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildCarousel(BuildContext context) {
    if (_featuredItems.isEmpty) {
      return _buildFallbackSlide(context);
    }

    return SizedBox(
      height: _featureHeight(context),
      child: PageView.builder(
        controller: _carouselController,
        itemCount: _featuredItems.length,
        onPageChanged: (index) => setState(() => _carouselIndex = index),
        itemBuilder: (context, index) {
          final item = _featuredItems[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: LiquidGlassContainer(
              borderRadius: 24,
              blurSigma: 16,
              glowColor: const Color(0xFFDF762D),
              customGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFE26B1E).withValues(alpha: 0.94),
                  const Color(0xFFFF8B38).withValues(alpha: 0.82),
                ],
              ),
              borderGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.45, 1.0],
                colors: [
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.30),
                  const Color(0xFFFFC093).withValues(alpha: 0.50),
                ],
              ),
              onTap: () => widget.onItemSelected(item),
              child: Stack(
                children: [
                  // Specular angled light shine streak
                  Positioned(
                    top: -45,
                    left: -30,
                    right: -30,
                    height: 100,
                    child: Transform.rotate(
                      angle: -0.25,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.35),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Glowing liquid refraction orb
                  Positioned(
                    right: -25,
                    bottom: -35,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .24),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .5),
                                    width: 1.0,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bolt_rounded,
                                        size: 13, color: Colors.white),
                                    SizedBox(width: 3),
                                    Text(
                                      'POPULAR',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .7,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    width: 1.0,
                                  ),
                                ),
                                child: Tooltip(
                                  message: item.rateText,
                                  child: Text(
                                    catalogPriceLabel(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Rent Now',
                                      style: TextStyle(
                                        color: Color(0xFFDF762D),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 14,
                                      color: Color(0xFFDF762D),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: item.buildImage(
                            fit: BoxFit.contain,
                            height: 136,
                            width: 145,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _featureHeight(BuildContext context) =>
      170 *
      (MediaQuery.textScalerOf(context).scale(14) / 14)
          .clamp(1.0, double.infinity);

  Widget _buildFallbackSlide(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Material(
          color: AppTheme.brandOrange,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onBrowse,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: _featureHeight(context)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Ready for a fun day?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Find sports gear and games to rent.',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .9)),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Browse equipment  ›',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.sports_basketball_rounded,
                        size: 82, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildRentalListSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<RentalModel> rentals,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final preview = rentals.take(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: widget.onViewRentals,
                child: const Text('View all'),
              ),
            ],
          ),
        ),
        for (final rental in preview)
          _buildRentalTile(context, rental,
              margin: const EdgeInsets.fromLTRB(18, 0, 18, 10)),
      ],
    );
  }

  String _activeRentalDetail(RentalModel rental) {
    if (rental.dueDate.millisecondsSinceEpoch <= 0) {
      if (rental.hasPendingReturnRequest) {
        return 'Return requested · waiting for admin receipt';
      }
      return 'Return time not recorded';
    }

    final remaining = rental.dueDate.difference(DateTime.now());
    if (remaining.isNegative) {
      return 'Overdue by ${_durationLabel(remaining)}';
    }
    if (remaining <= const Duration(hours: 24)) {
      return 'Due in ${_durationLabel(remaining)}';
    }
    return 'Return by ${_date(rental.dueDate)}';
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes.abs();
    if (minutes < 60) return '${minutes == 0 ? 1 : minutes}m';
    final days = minutes ~/ (24 * 60);
    final hours = (minutes % (24 * 60)) ~/ 60;
    final remainder = minutes % 60;
    if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    return remainder > 0 ? '${hours}h ${remainder}m' : '${hours}h';
  }

  Widget _buildRentalTile(
    BuildContext context,
    RentalModel rental, {
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(18, 0, 18, 10),
  }) {
    final item = _catalogItems.where((item) =>
        item.id == rental.itemId ||
        (rental.stockGroupId.isNotEmpty &&
            item.stockGroupId == rental.stockGroupId));
    final imageItem = item.isEmpty ? null : item.first;
    final code = rental.displayReference;
    final detail = rental.isActive
        ? _activeRentalDetail(rental)
        : rental.canCancel && rental.holdExpiresAt != null
            ? 'Handoff by ${_date(rental.holdExpiresAt!)}'
            : rental.isAwaitingPickup
                ? 'Approved · awaiting handoff'
                : rental.isAwaitingInspection
                    ? 'Returned · inspection pending'
                    : rental.isPendingVerification
                        ? 'Waiting for terminal confirmation'
                        : 'Waiting for admin approval';
    final dueDateIsSet = rental.dueDate.millisecondsSinceEpoch > 0;
    final overdue = rental.isActive &&
        dueDateIsSet &&
        DateTime.now().isAfter(rental.dueDate);
    final dueSoon = rental.isActive &&
        dueDateIsSet &&
        !overdue &&
        rental.dueDate.difference(DateTime.now()) <= const Duration(hours: 24);
    final detailColor = overdue
        ? Theme.of(context).colorScheme.error
        : dueSoon
            ? AppTheme.brandOrange
            : Theme.of(context).colorScheme.onSurfaceVariant;

    return GlassCard(
      margin: margin,
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      blurSigma: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 62,
                    height: 62,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkSurfaceVariant
                        : const Color(0xFFF1F5F9),
                    child: imageItem?.buildImage(
                          fit: BoxFit.cover,
                          width: 62,
                          height: 62,
                        ) ??
                        Icon(Icons.inventory_2_outlined,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rental.itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!rental.isActive || !dueDateIsSet) ...[
                        const SizedBox(height: 7),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: overdue || dueSoon
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: detailColor,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child:
                            RentalStatusBadge(status: rental.normalizedStatus),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (rental.isActive && dueDateIsSet) ...[
              const SizedBox(height: 12),
              _RentalCountdownProgress(rental: rental),
            ],
            if (rental.isActive &&
                rental.hasPendingReturnRequest &&
                dueDateIsSet) ...[
              const SizedBox(height: 5),
              Text(
                'Return requested · waiting for admin receipt',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
    );
  }

  Widget _buildSignInCard(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: LiquidGlassContainer(
          borderRadius: 20,
          blurSigma: 14,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFDF762D).withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    size: 22, color: Color(0xFFDF762D)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Sign in to see your rental activity.',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );

  Widget _buildNoRentalsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: GlassCard(
        borderRadius: 16,
        blurSigma: 12,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFDF762D)
                    .withValues(alpha: isDark ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: Color(0xFFDF762D),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No active rentals right now.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ready to play',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRentalsLoadingCard(BuildContext context) => const Card(
        margin: EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Loading your rentals…'),
            ],
          ),
        ),
      );

  Widget _buildRentalError(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Could not load your rentals. Pull down to try again.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              IconButton(
                tooltip: 'Retry',
                onPressed: _loadHome,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      );
}

class _RentalCountdownProgress extends StatefulWidget {
  const _RentalCountdownProgress({required this.rental});

  final RentalModel rental;

  @override
  State<_RentalCountdownProgress> createState() =>
      _RentalCountdownProgressState();
}

class _RentalCountdownProgressState extends State<_RentalCountdownProgress> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _countdownLabel(Duration duration) {
    final seconds = (duration.inMilliseconds.abs() + 999) ~/ 1000;
    final days = seconds ~/ Duration.secondsPerDay;
    final hours = (seconds ~/ Duration.secondsPerHour) % 24;
    final minutes = (seconds ~/ Duration.secondsPerMinute) % 60;
    final remainder = seconds % 60;
    final clock =
        '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(remainder)}';
    return days > 0 ? '${days}d $clock' : clock;
  }

  @override
  Widget build(BuildContext context) {
    final rental = widget.rental;
    final remaining = rental.dueDate.difference(_now);
    final overdue = remaining.isNegative;
    final scheme = Theme.of(context).colorScheme;
    final color = overdue
        ? scheme.error
        : remaining <= const Duration(hours: 24)
            ? AppTheme.brandOrange
            : scheme.primary;
    final totalDuration = rental.dueDate.difference(rental.startDate);
    final progress = rental.startDate.millisecondsSinceEpoch <= 0 ||
            totalDuration.inMilliseconds <= 0
        ? null
        : (remaining.inMilliseconds / totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 16, color: color),
            const SizedBox(width: 5),
            Text(
              overdue ? 'Overdue by' : 'Due in',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              _countdownLabel(remaining),
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
              semanticsLabel: 'Rental time remaining',
              semanticsValue: '${(progress * 100).round()} percent',
            ),
          ),
        ],
      ],
    );
  }
}
