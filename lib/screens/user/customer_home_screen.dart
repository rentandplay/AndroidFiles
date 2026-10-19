import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/liquid_glass.dart';
import '../profile/profile_screen.dart';
import '../rental/rental_history_screen.dart';
import 'active_rentals_screen.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'item_details_screen.dart';
import '../auth/login_screen.dart';

/// Keeps the customer's main destinations within reach on small screens.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _selectedIndex = 0;
  late bool _isSignedIn;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<CatalogScreenState> _catalogKey =
      GlobalKey<CatalogScreenState>();
  final List<Widget?> _pages = List<Widget?>.filled(5, null);

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.storefront_outlined),
      selectedIcon: Icon(Icons.storefront_rounded),
      label: 'Browse',
    ),
    NavigationDestination(
      icon: Icon(Icons.shopping_bag_outlined),
      selectedIcon: Icon(Icons.shopping_bag_rounded),
      label: 'Rentals',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      selectedIcon: Icon(Icons.history),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Profile',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _isSignedIn =
        Provider.of<AuthService>(context, listen: false).currentUser != null;
    _selectedIndex = _isSignedIn ? 0 : 1;
    _pages[_selectedIndex] = _pageFor(_selectedIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isSignedIn = Provider.of<AuthService>(context).currentUser != null;
    if (_isSignedIn == isSignedIn) return;

    _isSignedIn = isSignedIn;
    if (!isSignedIn) {
      _selectedIndex = 1;
      _pages[1] ??= _pageFor(1);
    }
  }

  Widget _pageFor(int index) => switch (index) {
        0 => HomeScreen(
            key: _homeKey,
            onBrowse: () => _selectPage(1),
            onViewRentals: () => _selectPage(2),
            onItemSelected: _openItem,
            onBrowseCategory: _browseCategory,
          ),
        1 => CatalogScreen(key: _catalogKey),
        2 => ActiveRentalsScreen(
            key: const ValueKey('customer-active-rentals'),
            onBrowse: () => _selectPage(1),
            isActive: _selectedIndex == 2,
          ),
        3 => RentalHistoryScreen(onBrowse: () => _selectPage(1)),
        _ => const ProfileScreen(showBackButton: false),
      };

  void _openItem(ItemModel item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item)),
    ).then((_) {
      if (mounted) _homeKey.currentState?.refresh();
    });
  }

  void _browseCategory(String category) {
    if (_pages[1] == null) {
      _pages[1] = CatalogScreen(key: _catalogKey, initialCategory: category);
    } else {
      _catalogKey.currentState?.selectCategory(category);
    }
    _selectPage(1);
  }

  void _selectPage(int index) {
    if (_pages[index] == null) _pages[index] = _pageFor(index);
    if (index == 0) _homeKey.currentState?.refresh();
    setState(() {
      _selectedIndex = index;
      if (_pages[2] != null) _pages[2] = _pageFor(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = Provider.of<AuthService>(context).currentUser != null;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBody: true,
      body: isSignedIn
          ? IndexedStack(
              index: _selectedIndex,
              children: [
                for (final page in _pages) page ?? const SizedBox.shrink(),
              ],
            )
          : _pages[1]!,
      bottomNavigationBar: _buildFloatingDock(context, isSignedIn),
    );
  }

  static const _signedInTabs = [
    LiquidGlassTab(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    LiquidGlassTab(
      label: 'Browse',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
    ),
    LiquidGlassTab(
      label: 'Rentals',
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag_rounded,
    ),
    LiquidGlassTab(
      label: 'History',
      icon: Icons.history,
      activeIcon: Icons.history_rounded,
    ),
    LiquidGlassTab(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  static const _guestTabs = [
    LiquidGlassTab(
      label: 'Browse',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
    ),
    LiquidGlassTab(
      label: 'Rentals',
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag_rounded,
    ),
    LiquidGlassTab(
      label: 'Account',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  Widget _buildFloatingDock(BuildContext context, bool isSignedIn) {
    if (!isSignedIn) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: LiquidGlassBottomNavBar(
            selectedIndex: 0,
            tabs: _guestTabs,
            onTabSelected: (index) {
              if (index == 1) {
                _promptGuestSignIn(
                  context,
                  title: 'Rentals & Bookings',
                  message:
                      'Sign in to see your active rentals, due dates, and equipment receipts.',
                );
              } else if (index == 2) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: LiquidGlassBottomNavBar(
          selectedIndex: _selectedIndex,
          tabs: _signedInTabs,
          onTabSelected: _selectPage,
        ),
      ),
    );
  }

  void _promptGuestSignIn(BuildContext context,
      {required String title, required String message}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFDF762D).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    size: 28, color: Color(0xFFDF762D)),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    height: 1.4),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A3D), Color(0xFFDF762D)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDF762D).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: const Text(
                      'Sign in / Create Account',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Continue Browsing',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
