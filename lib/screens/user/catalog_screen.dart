import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../auth/id_verification_screen.dart';
import 'item_details_screen.dart';
import 'active_rentals_screen.dart';
import '../admin/admin_dashboard_screen.dart';
import '../alerts/alerts_screen.dart';
import '../rental/rental_history_screen.dart';
import '../profile/profile_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String selectedCategory = 'All';
  final List<String> categories = [
    'All',
    'Sports',
    'Cards',
    'Board Games',
    'Tech Rentals',
  ];

  late List<ItemModel> catalogItems;

  @override
  void initState() {
    super.initState();
    catalogItems = ItemModel.getInitialCatalog();
  }

  List<ItemModel> get filteredItems {
    if (selectedCategory == 'All') {
      return catalogItems;
    }
    return catalogItems.where((item) => item.category == selectedCategory).toList();
  }

  void _handleRentalClick(ItemModel item) async {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to rent or purchase items.'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    UserModel? userModel = await authService.getCurrentUserModel();
    if (!mounted) return;

    if (userModel == null || !userModel.hasAcceptedTerms) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please review rental policies and accept terms before renting.'),
        ),
      );
      navigator.push(
        MaterialPageRoute(
          builder: (_) => IdVerificationScreen(userModel: userModel),
        ),
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ItemDetailsScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Clean Unclipped Brand Logo in Header
            SizedBox(
              height: 32,
              child: Image.asset(
                'assets/images/logo_rent_and_play.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.sports_esports,
                    color: Theme.of(context).primaryColor,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Rent & Play',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
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
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.shopping_bag_outlined, size: 22),
              tooltip: 'My Active Rentals',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ActiveRentalsScreen()),
                );
              },
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.notifications_outlined, size: 22),
              tooltip: 'Alerts & Timers',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlertsScreen()),
                );
              },
            ),
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 22),
              tooltip: 'More Options',
              onSelected: (value) async {
                if (value == 'profile') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                } else if (value == 'history') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RentalHistoryScreen()),
                  );
                } else if (value == 'admin') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                  );
                } else if (value == 'logout') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged out successfully.')),
                  );
                  authService.logout();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 20, color: Colors.black87),
                      SizedBox(width: 10),
                      Text('Profile & Settings'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'history',
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 20, color: Colors.black87),
                      SizedBox(width: 10),
                      Text('Rental History'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'admin',
                  child: FutureBuilder<UserModel?>(
                    future: authService.getCurrentUserModel(),
                    builder: (context, snapshot) {
                      final isAdmin = snapshot.data?.role.toLowerCase() == 'admin';
                      return Row(
                        children: [
                          Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 20,
                            color: isAdmin ? const Color(0xFFF57C00) : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Operator Dashboard',
                            style: TextStyle(
                              color: isAdmin ? const Color(0xFFF57C00) : Colors.grey,
                              fontWeight: isAdmin ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 20, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Category Selector Bar
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = selectedCategory == category;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    selectedColor: Theme.of(context).primaryColor,
                    backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
                    side: BorderSide(color: isDark ? const Color(0xFF1E2C42) : Colors.grey.shade300),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? const Color(0xFFF8FAFC) : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          selectedCategory = category;
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),

          // Item Catalog Grid
          Expanded(
            child: filteredItems.isEmpty
                ? const Center(child: Text('No items found in this category.'))
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.64,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return _buildItemCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    final isAvailable = item.status.toLowerCase() == 'available';

    Color statusColor;
    if (item.status.toLowerCase() == 'available') {
      statusColor = Colors.green;
    } else if (item.status.toLowerCase() == 'rented') {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.red;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  height: 110,
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  child: item.buildImage(fit: BoxFit.cover, height: 110),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.category,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.rateText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAvailable ? const Color(0xFFF57C00) : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: isAvailable ? () => _handleRentalClick(item) : null,
                      child: Text(
                        item.isForSale ? 'Rent / Buy' : 'Rent Now',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
}
