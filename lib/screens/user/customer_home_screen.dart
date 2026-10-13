import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_model.dart';
import '../../services/auth_service.dart';
import '../profile/profile_screen.dart';
import '../rental/rental_history_screen.dart';
import 'active_rentals_screen.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'item_details_screen.dart';

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
      body: isSignedIn
          ? IndexedStack(
              index: _selectedIndex,
              children: [
                for (final page in _pages) page ?? const SizedBox.shrink(),
              ],
            )
          : _pages[1]!,
      bottomNavigationBar: isSignedIn
          ? NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 72,
                backgroundColor: scheme.surface,
                indicatorColor:
                    scheme.primary.withValues(alpha: isDark ? .2 : .12),
                surfaceTintColor: Colors.transparent,
                iconTheme:
                    WidgetStateProperty.resolveWith((states) => IconThemeData(
                          color: states.contains(WidgetState.selected)
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        )),
                labelTextStyle:
                    WidgetStateProperty.resolveWith((states) => TextStyle(
                          color: states.contains(WidgetState.selected)
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: states.contains(WidgetState.selected)
                              ? FontWeight.w700
                              : FontWeight.w500,
                        )),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                destinations: _destinations,
                onDestinationSelected: _selectPage,
              ),
            )
          : null,
    );
  }
}
