

import '../../widgets/brand_hero_header.dart';
import '../../widgets/customer_home_backdrop.dart';
import '../../widgets/home_rental_pager.dart';
import '../../widgets/premium_animations.dart';
import 'package:flutter/services.dart';
import '../../widgets/glass_app_bar.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../widgets/live_business_settings.dart';
import '../../services/server_clock.dart';

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
import '../shared/support_chat_screen.dart';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

bool get _isHomeTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

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

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _headerBackdropKey = BackdropKey();
  final _contentBackdropKey = BackdropKey();
  final PageController _carouselController =
      PageController(viewportFraction: .92);
  List<ItemModel> _catalogItems = [];
  List<ItemModel> _featuredItems = [];
  List<RentalModel> _rentals = [];
  bool _loading = true;
  String _rentalError = '';
  String _catalogError = '';
  int _carouselIndex = 0;
  Timer? _carouselTimer;
  Timer? _rentalPollTimer;

  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadHome(quiet: true);
    }
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    _syncRentalPollTimer();
    if (_featuredItems.length <= 1) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_carouselController.hasClients || _featuredItems.length <= 1) return;
      final nextIndex = (_carouselIndex + 1) % _featuredItems.length;
      _carouselController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _resetCarouselTimer() {
    _carouselTimer?.cancel();
    _startCarouselTimer();
  }

  void _syncRentalPollTimer() {
    _rentalPollTimer?.cancel();
    _rentalPollTimer = null;
    if (_isHomeTest || !_rentals.any((r) => r.isOpen)) return;
    _rentalPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _loadHome(quiet: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _carouselTimer?.cancel();
    _rentalPollTimer?.cancel();
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

      // Filter and prioritize popular items for the carousel
      final popular = available.where((item) => item.isPopular).toList();
      popular.sort((a, b) {
        final aBadminton = a.name.toLowerCase().contains('badminton');
        final bBadminton = b.name.toLowerCase().contains('badminton');
        if (aBadminton && !bBadminton) return -1;
        if (!aBadminton && bBadminton) return 1;
        return a.name.compareTo(b.name);
      });

      if (popular.isNotEmpty) {
        final remaining = available.where((item) => !item.isPopular).toList();
        items = [...popular, ...remaining].take(6).toList();
      } else {
        items = available.take(6).toList();
      }
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
    _startCarouselTimer();
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
      ServerClock.instance.now.isAfter(rental.holdExpiresAt!);

  String _date(DateTime value) =>
      DateFormat('MMM d, h:mm a').format(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final scheme = Theme.of(context).colorScheme;
    final activeRentals = _activeRentals;
    final currentRequests = _currentRequests;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final safeTop = MediaQuery.of(context).padding.top;
    return LiquidGlassScope(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0D1219) : const Color(0xFFFBF8F5),
        body: RefreshIndicator(
          edgeOffset: safeTop + 54,
          onRefresh: _loadHome,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // Crisp folded ribbon artwork, with the glass controls above it.
              CustomerHomeHeroBackground(
                backdropKey: _headerBackdropKey,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 44),
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
                              HeaderActionPod(
                                podBg: Colors.white.withValues(alpha: 0.16),
                                podBorder: Colors.white.withValues(alpha: 0.25),
                                iconColor: Colors.white,
                                tooltip: 'Support chat',
                                icon: Icons.chat_bubble_outline_rounded,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const SupportInboxScreen()),
                                ),
                              ),
                              const SizedBox(width: 6),
                              HeaderActionPod(
                                podBg: Colors.white.withValues(alpha: 0.16),
                                podBorder: Colors.white.withValues(alpha: 0.25),
                                iconColor: Colors.white,
                                tooltip: 'Search equipment',
                                icon: Icons.search_rounded,
                                onTap: widget.onBrowse,
                              ),
                              const SizedBox(width: 6),
                              const RentalNotificationBellPod(
                                podBg: Color(0x28FFFFFF),
                                podBorder: Color(0x40FFFFFF),
                                iconColor: Colors.white,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // One continuous body curve and a scene visible through the clear cards.
              Transform.translate(
                offset: const Offset(0, -CustomerHomeTopClipper.overlap),
                child: CustomerHomeScene(
                    backdropKey: _contentBackdropKey,
                    child: Container(
                      padding: const EdgeInsets.only(top: 38, bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StaggeredSlideFade(
                            index: 0,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LiveBusinessSettings(
                                      api: _api,
                                      builder: (context, settings) =>
                                          LiveAnnouncementBanner(
                                              settings: settings.values)),
                                  Text(
                                    user?.displayName?.trim().isNotEmpty == true
                                        ? 'Welcome back, ${user!.displayName!.trim().split(' ').first}'
                                        : 'Welcome to Rent & Play',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 22,
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
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          StaggeredSlideFade(
                            index: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCarousel(context),
                                if (_featuredItems.length > 1) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                      _featuredItems.length,
                                      (index) => GestureDetector(
                                        onTap: () {
                                          _carouselController.animateToPage(
                                            index,
                                            duration: const Duration(
                                                milliseconds: 350),
                                            curve: Curves.easeInOut,
                                          );
                                          _resetCarouselTimer();
                                        },
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 240),
                                          width:
                                              index == _carouselIndex ? 22 : 6,
                                          height: 6,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          decoration: BoxDecoration(
                                            color: index == _carouselIndex
                                                ? const Color(0xFFDF762D)
                                                : (isDark
                                                    ? const Color(0xFF45362B)
                                                    : const Color(0xFFE2D6CB)),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          StaggeredSlideFade(
                            index: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (user != null &&
                                    _rentalError.isEmpty &&
                                    activeRentals.isNotEmpty)
                                  _buildRentalListSection(
                                    context,
                                    title: 'Active rentals',
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
                                    rentals: currentRequests,
                                  )
                                else if (activeRentals.isEmpty)
                                  _buildNoRentalsCard(context),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          StaggeredSlideFade(
                            index: 3,
                            child: HomeDiscovery(
                              items: _catalogItems,
                              featuredIds:
                                  _featuredItems.map((item) => item.id).toSet(),
                              loading: _loading,
                              hasError: _catalogError.isNotEmpty,
                              onBrowse: widget.onBrowse,
                              onCategorySelected: widget.onBrowseCategory ??
                                  (_) => widget.onBrowse(),
                              onItemSelected: widget.onItemSelected,
                              onRetry: _loadHome,
                            ),
                          ),
                          const SizedBox(height: 90),
                        ],
                      ),
                    )),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  String _formatPopularRate(ItemModel item) {
    if (item.rateHourly > 0) {
      final amount = item.rateHourly.truncateToDouble() == item.rateHourly
          ? item.rateHourly.toInt().toString()
          : item.rateHourly.toStringAsFixed(2);
      return '₱$amount / Per hour';
    }
    return catalogPriceLabel(item);
  }

  Widget _buildCarousel(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_featuredItems.isEmpty) {
      return _buildFallbackSlide(context);
    }

    return SizedBox(
      height: _featureHeight(context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            _carouselTimer?.cancel();
          } else if (notification is ScrollEndNotification) {
            _startCarouselTimer();
          }
          return false;
        },
        child: PageView.builder(
          clipBehavior: Clip.none,
          controller: _carouselController,
          itemCount: _featuredItems.length,
          onPageChanged: (index) {
            setState(() => _carouselIndex = index);
            _resetCarouselTimer();
          },
          itemBuilder: (context, index) {
            final item = _featuredItems[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Base card surface (with top margin so 3D image pops up over the top rim)
                  Positioned.fill(
                    top: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.55, 1.0],
                          colors: dark
                              ? const [
                                  Color(0xFF231C18),
                                  Color(0xFF1A1F2C),
                                  Color(0xFF281B14),
                                ]
                              : const [
                                  Color(0xFFFFFDFB),
                                  Color(0xFFFFF6ED),
                                  Color(0xFFFCEBD9),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: dark
                              ? const Color(0xFFDF762D).withValues(alpha: 0.34)
                              : const Color(0xFFDF762D).withValues(alpha: 0.26),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: dark
                                ? Colors.black.withValues(alpha: 0.42)
                                : const Color(0xFFDF762D).withValues(alpha: 0.14),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          // Warm spotlight aura behind the 3D floating product
                          Positioned(
                            right: -18,
                            top: -18,
                            bottom: -18,
                            width: 170,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      const Color(0xFFFF8A3D)
                                          .withValues(alpha: dark ? 0.24 : 0.22),
                                      const Color(0xFFDF762D)
                                          .withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => widget.onItemSelected(item),
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Left side: Details
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // ⚡ POPULAR badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 9, vertical: 3.5),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: dark
                                                    ? const [
                                                        Color(0xFF432B1D),
                                                        Color(0xFF2F1F16),
                                                      ]
                                                    : const [
                                                        Color(0xFFFFECD9),
                                                        Color(0xFFFDE0C3),
                                                      ],
                                              ),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: const Color(0xFFDF762D)
                                                    .withValues(alpha: 0.35),
                                                width: 0.9,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.bolt_rounded,
                                                  size: 13,
                                                  color: Color(0xFFDF762D),
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  'POPULAR',
                                                  style: TextStyle(
                                                    color: dark
                                                        ? const Color(0xFFFFD8BA)
                                                        : const Color(0xFF8C3B0C),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.6,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          // Item Name
                                          Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: dark
                                                  ? const Color(0xFFFFF5ED)
                                                  : const Color(0xFF1A1512),
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.4,
                                              height: 1.15,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          // Price label with tabular numerals
                                          Text(
                                            _formatPopularRate(item),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: dark
                                                  ? const Color(0xFFFFB37C)
                                                  : const Color(0xFFD9651B),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.2,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          // Vibrant gradient CTA pill
                                          InkWell(
                                            onTap: () => widget.onItemSelected(item),
                                            borderRadius: BorderRadius.circular(20),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 6.5),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Color(0xFFFF8A3D),
                                                    Color(0xFFDF762D),
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(20),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFFDF762D)
                                                        .withValues(alpha: 0.35),
                                                    blurRadius: 10,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: const FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'View details',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w800,
                                                        letterSpacing: -0.1,
                                                      ),
                                                    ),
                                                    SizedBox(width: 5),
                                                    Icon(
                                                      Icons.arrow_forward_rounded,
                                                      size: 13,
                                                      color: Colors.white,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Right side spacer (reserved for 3D floating pop-up image)
                                    const Expanded(
                                      flex: 5,
                                      child: SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3D Floating Pop-Up Image Layer (positioned over the right side)
                  Positioned(
                    top: 0,
                    right: 6,
                    bottom: 4,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => widget.onItemSelected(item),
                      child: _Floating3DCardImage(
                        item: item,
                        dark: dark,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double _featureHeight(BuildContext context) =>
      168 *
      (MediaQuery.textScalerOf(context).scale(14) / 14)
          .clamp(1.0, 1.25);


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
    required List<RentalModel> rentals,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return HomeRentalPager(
      key: ValueKey(title),
      title: title,
      itemCount: rentals.length,
      contentHeight: 136 +
          (scale.clamp(1.0, 3.0) - 1) * 76 +
          (rentals.any((rental) => rental.hasPendingReturnRequest) ? 24 : 0),
      itemBuilder: (context, index) =>
          _buildRentalTile(context, rentals[index]),
    );
  }

  String _activeRentalDetail(RentalModel rental) {
    if (rental.dueDate.millisecondsSinceEpoch <= 0) {
      if (rental.hasPendingReturnRequest) {
        return 'Return requested · waiting for admin receipt';
      }
      return 'Return time not recorded';
    }

    final remaining = rental.dueDate.difference(ServerClock.instance.now);
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
    RentalModel rental,
  ) {
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
        ServerClock.instance.now.isAfter(rental.dueDate);
    final dueSoon = rental.isActive &&
        dueDateIsSet &&
        !overdue &&
        rental.dueDate.difference(ServerClock.instance.now) <=
            const Duration(hours: 2);
    final detailColor = overdue
        ? Theme.of(context).colorScheme.error
        : dueSoon
            ? AppTheme.brandOrange
            : Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                      child: overdue && !rental.hasPendingReturnRequest
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('Overdue',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          Theme.of(context).colorScheme.error)),
                            )
                          : RentalStatusBadge(status: rental.normalizedStatus),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (rental.isActive && dueDateIsSet) ...[
            const SizedBox(height: 10),
            RepaintBoundary(child: _RentalCountdownProgress(rental: rental)),
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
          ] else if (rental.isActive &&
              rental.hasPendingExtensionRequest &&
              dueDateIsSet) ...[
            const SizedBox(height: 5),
            Text(
              'Extension requested · awaiting admin approval',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.brandOrange,
              ),
            ),
          ] else if (rental.isActive &&
              rental.effectiveTotalExtendedMinutes > 0 &&
              dueDateIsSet) ...[
            const SizedBox(height: 5),
            Text(
              () {
                final mins = rental.effectiveTotalExtendedMinutes;
                final added = mins < 60
                    ? '${mins}m'
                    : mins % 60 == 0
                        ? '${mins ~/ 60}h'
                        : '${mins ~/ 60}h ${mins % 60}m';
                return 'Extended · +$added added to timer';
              }(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF059669),
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
      child: PremiumPressable(
        onTap: widget.onBrowse,
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
              DecoratedBox(
                decoration: BoxDecoration(boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: .10),
                    blurRadius: 12,
                  ),
                ]),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRentalsLoadingCard(BuildContext context) => const GlassCard(
        margin: EdgeInsets.fromLTRB(18, 0, 18, 12),
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
      );

  Widget _buildRentalError(BuildContext context) => GlassCard(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
    _now = ServerClock.instance.now;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = ServerClock.instance.now);
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
        : remaining <= const Duration(hours: 2)
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
            _HomeCountdownRing(
              progress: overdue ? 1.0 : (progress ?? 0.5),
              color: color,
              trackColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                overdue ? 'Overdue by' : 'Due in',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _countdownLabel(remaining),
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (progress != null && !overdue) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: progress, end: progress),
              builder: (context, animatedProgress, _) => LinearProgressIndicator(
                value: animatedProgress,
                minHeight: 6,
                color: color,
                backgroundColor: scheme.surfaceContainerHighest,
                semanticsLabel: 'Rental time remaining',
                semanticsValue: '${(animatedProgress * 100).round()} percent',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HomeCountdownRing extends StatelessWidget {
  const _HomeCountdownRing({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _HomeCountdownRingPainter(
          progress: progress,
          color: color,
          trackColor: trackColor,
        ),
      ),
    );
  }
}

class _HomeCountdownRingPainter extends CustomPainter {
  const _HomeCountdownRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - 2.6) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HomeCountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

class _Floating3DCardImage extends StatefulWidget {
  final ItemModel item;
  final bool dark;

  const _Floating3DCardImage({
    required this.item,
    required this.dark,
  });

  @override
  State<_Floating3DCardImage> createState() => _Floating3DCardImageState();
}

class _Floating3DCardImageState extends State<_Floating3DCardImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _anim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
    if (!_isHomeTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final progress = _anim.value;
        final floatY = progress * 7.0;
        final tilt = (progress - 0.5) * 0.04;

        return SizedBox(
          width: 138,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Contact floor shadow on card surface (reacts dynamically to float height)
              Positioned(
                bottom: 10,
                child: Container(
                  width: 66 + (progress * 10),
                  height: 12 - (progress * 2),
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.all(Radius.elliptical(50, 10)),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.dark ? Colors.black : const Color(0xFF2C1810))
                            .withValues(alpha: widget.dark
                                ? (0.42 - progress * 0.10)
                                : (0.20 - progress * 0.06)),
                        blurRadius: 14 + (progress * 4),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),

              // 3D Floating Pop-Up Image
              Positioned(
                top: 0,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(0.0, -floatY - 4.0, 0.0, 1.0)
                    ..rotateZ(tilt),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: (widget.dark ? Colors.black : const Color(0xFF2C1810))
                              .withValues(alpha: widget.dark ? 0.32 : 0.15),
                          blurRadius: 18,
                          offset: const Offset(2, 6),
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Hero(
                      tag: 'item-image-${widget.item.id}',
                      child: widget.item.buildImage(
                        fit: BoxFit.contain,
                        height: 126,
                        width: 132,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
