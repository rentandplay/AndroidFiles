import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/item_model.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../theme/app_theme.dart';
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
  });

  final VoidCallback onBrowse;
  final VoidCallback onViewRentals;
  final ValueChanged<ItemModel> onItemSelected;

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
  int _carouselIndex = 0;

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

    try {
      final records = await MobileApiService.instance.catalog();
      catalogItems = records
          .map((row) => ItemModel.fromMap(row, id: row['id'].toString()))
          .toList();
      items = catalogItems
          .where((item) => item.status.toLowerCase() == 'available')
          .take(5)
          .toList();
    } catch (_) {
      // Keep the rental summary usable if the featured catalog cannot load.
    }

    if (isSignedIn) {
      try {
        rentals = await MobileApiService.instance.listRentals();
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
                                letterSpacing: -.45,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find something fun for your next day out.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
                  if (user != null &&
                      !_loading &&
                      _rentalError.isEmpty &&
                      activeRentals.isEmpty &&
                      currentRequests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onBrowse,
                          icon: const Icon(Icons.storefront_outlined),
                          label: const Text('Browse equipment'),
                        ),
                      ),
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
      height: 194,
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
                        padding: const EdgeInsets.fromLTRB(20, 18, 8, 14),
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
                                      fontSize: 20,
                                      height: 1.05,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Tooltip(
                                    message: item.rateText,
                                    child: Text(
                                      item.rateText,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: .9),
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
                                height: 150,
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

  Widget _buildFallbackSlide(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Material(
          color: AppTheme.brandOrange,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onBrowse,
            child: SizedBox(
              height: 194,
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
                              fontSize: 22,
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
    final item = _catalogItems.where((item) => item.id == rental.itemId);
    final imageItem = item.isEmpty ? null : item.first;
    final code =
        rental.rentalCode.isNotEmpty ? rental.rentalCode : rental.rentalId;
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
        child: Row(
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RentalStatusBadge(status: rental.normalizedStatus),
                  ),
                  if (rental.isActive &&
                      rental.hasPendingReturnRequest &&
                      dueDateIsSet) ...[
                    const SizedBox(height: 4),
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
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.sports_esports_outlined,
                  size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'No active rentals right now. Requests and equipment in your care will appear here.',
                  style: TextStyle(height: 1.35),
                ),
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
