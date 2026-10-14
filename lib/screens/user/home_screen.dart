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
import '../../widgets/notification_widgets.dart';
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

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    if (mounted) setState(() => _loading = true);
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

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const RentPlayWordmark(),
        actions: [
          if (user == null)
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text('Sign in'),
            )
          else
            const RentalNotificationBell(),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadHome,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName?.trim().isNotEmpty == true
                              ? 'Welcome back, ${user!.displayName!.trim().split(' ').first}!'
                              : 'Welcome to Rent & Play!',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                letterSpacing: -.45,
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
                ],
              ),
            ),
          ),
        ],
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
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => widget.onItemSelected(item),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.brandOrange,
                        Color(0xFFF58A32),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -18,
                        bottom: -42,
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: .12),
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
                                        horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: .18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'FEATURED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .7,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      height: 1.05,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Tooltip(
                                    message: item.rateText,
                                    child: Text(
                                      catalogPriceLabel(item),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .9),
                                        fontSize: 12,
                                        height: 1.15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextButton(
                                    onPressed: () =>
                                        widget.onItemSelected(item),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'View item  ›',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700),
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

    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(13),
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
      ),
    );
  }

  Widget _buildSignInCard(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Sign in to see your rental activity.'),
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

  Widget _buildNoRentalsCard(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.shopping_bag_outlined,
                    size: 20, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your next game awaits',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('No active rentals right now.',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              )),
              IconButton(
                tooltip: 'Browse equipment',
                onPressed: widget.onBrowse,
                icon: Icon(Icons.arrow_forward_rounded,
                    size: 20, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      );

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
