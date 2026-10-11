import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_firestore_service.dart';
import '../../widgets/notification_widgets.dart';
import 'equipment_list_screen.dart';
import 'rental_admin_view.dart';
import '../profile/profile_screen.dart';

/// Lightweight staff counter for the Android app.
///
/// Inventory browsing and label printing are available on mobile. Detailed
/// inventory editing, customer, rate, report, and account administration lives
/// in the web workspace. This screen keeps the mobile tools needed at the
/// counter: review rentals, scan QR codes, hand off equipment, and process
/// returns.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.onSignedOut,
    this.api,
  });

  final VoidCallback onSignedOut;
  final AdminFirestoreService? api;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with WidgetsBindingObserver {
  AdminFirestoreService get _api =>
      widget.api ?? AdminFirestoreService.instance;
  Timer? _refreshTimer;
  Timer? _eventRefreshTimer;
  StreamSubscription<Map<String, dynamic>>? _rentalEvents;
  bool _appResumed = true;
  bool _refreshAgain = false;
  bool _forceNextRefresh = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _leaving = false;
  String _connectionError = '';
  Map<String, dynamic> _dashboard = {};
  Map<String, dynamic> _workspace = {};
  int _selectedIndex = 0;
  String? _requestedScanKind;
  int _scanRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _bootstrap();
  }

  @override
  void dispose() {
    _stopLiveUpdates();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!_api.hasSession) {
      _returnToLogin();
      return;
    }
    try {
      await _api.restoreAdminSession();
      await _loadWorkspace();
      if (mounted && !_leaving) _startLiveUpdates();
    } on AdminApiException catch (error) {
      if (_isAuthFailure(error)) {
        await _logout();
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _connectionError = error.message;
      });
      _startLiveUpdates();
    }
  }

  void _startLiveUpdates() {
    if (!_appResumed || _leaving || !_api.hasSession || _rentalEvents != null) {
      return;
    }
    _rentalEvents = _api.watchRentalEvents().listen((event) {
      if (!mounted || !_appResumed || _leaving) return;
      if (event['event'] == 'ready' || event['event'] == 'rental.changed') {
        _eventRefreshTimer?.cancel();
        _eventRefreshTimer = Timer(const Duration(milliseconds: 180), () {
          if (mounted && _appResumed && !_leaving) {
            unawaited(_loadWorkspace(quiet: true));
          }
        });
      }
    });
    // A foreground recovery check also picks up non-rental inventory edits.
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted && _appResumed && !_leaving) {
        unawaited(_loadWorkspace(quiet: true));
      }
    });
  }

  void _stopLiveUpdates() {
    _refreshTimer?.cancel();
    _eventRefreshTimer?.cancel();
    _rentalEvents?.cancel();
    _rentalEvents = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _stopLiveUpdates();
    if (_appResumed && !_leaving) {
      _startLiveUpdates();
      unawaited(_loadWorkspace(quiet: true));
    }
  }

  Future<void> _loadWorkspace(
      {bool quiet = false, bool forceRefresh = false}) async {
    if (_leaving) return;
    if (_refreshing) {
      _refreshAgain = true;
      _forceNextRefresh = _forceNextRefresh || forceRefresh;
      return;
    }
    if (!_api.hasSession) {
      _returnToLogin();
      return;
    }
    _refreshing = true;
    if (!quiet && mounted) {
      setState(() {
        _loading = true;
        _connectionError = '';
      });
    }
    try {
      final workspace = await _api.loadWorkspace(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _dashboard = _api.dashboardFromWorkspace(workspace);
        _loading = false;
        _connectionError = '';
      });
    } on AdminApiException catch (error) {
      if (_isAuthFailure(error)) {
        await _logout();
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _connectionError = error.message;
      });
    } finally {
      _refreshing = false;
      if (_refreshAgain && mounted && _appResumed && !_leaving) {
        _refreshAgain = false;
        final force = _forceNextRefresh;
        _forceNextRefresh = false;
        unawaited(_loadWorkspace(quiet: true, forceRefresh: force));
      }
    }
  }

  Future<void> _refresh() => _loadWorkspace(forceRefresh: true);
  Future<void> _refreshAfterChange() => _loadWorkspace();

  Future<void> _logout() async {
    if (_leaving) return;
    _leaving = true;
    _stopLiveUpdates();
    try {
      await _api.signOut();
    } catch (error) {
      _leaving = false;
      _startLiveUpdates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sign out: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    widget.onSignedOut();
  }

  void _returnToLogin() {
    if (_leaving) return;
    _leaving = true;
    _stopLiveUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSignedOut();
    });
  }

  bool _isAuthFailure(AdminApiException error) =>
      error.statusCode == 401 ||
      (error.statusCode == 403 &&
          !error.message.startsWith('Firebase denied access.'));

  List<Map<String, dynamic>> get _rentals {
    final workspaceRows = _rows(_workspace['rentals']);
    return workspaceRows.isNotEmpty
        ? workspaceRows
        : _rows(_dashboard['rentals']);
  }

  int _countStatus(String status) =>
      _rentals.where((row) => row['status'] == status).length;

  void _selectTab(int index) {
    if (index == 2) {
      unawaited(_showScanOptions());
      return;
    }
    setState(() {
      _selectedIndex = index;
      _requestedScanKind = null;
    });
  }

  void _requestScan(String kind) {
    setState(() {
      _selectedIndex = kind == 'INVENTORY' ? 3 : 1;
      _requestedScanKind = kind;
      _scanRequestId++;
    });
  }

  void _consumeScanRequest() {
    if (!mounted || _requestedScanKind == null) return;
    setState(() => _requestedScanKind = null);
  }

  void _openEquipmentList() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Equipment')),
          body: EquipmentListScreen(
            items: _rows(_workspace['items']),
            onRefresh: _refresh,
          ),
        ),
      ),
    );
  }

  Future<void> _showScanOptions() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose what to scan',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.qr_code_2_rounded),
                ),
                title: const Text('Customer rental QR'),
                subtitle: const Text(
                  'Review a request or confirm a customer handoff.',
                ),
                onTap: () => Navigator.pop(sheetContext, 'BOOKING'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.inventory_2_outlined),
                ),
                title: const Text('Equipment QR'),
                subtitle: const Text(
                  'Prepare a unit, receive a return, or inspect it.',
                ),
                onTap: () => Navigator.pop(sheetContext, 'INVENTORY'),
              ),
            ],
          ),
        ),
      ),
    );
    if (kind != null && mounted) _requestScan(kind);
  }

  Widget _buildCurrentPage(Map<String, dynamic> user, bool isDark) {
    if (_loading && _workspace.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _AdminColors.orange),
      );
    }
    if (_selectedIndex == 1) return _buildTransactionPage(returns: false);
    if (_selectedIndex == 3) return _buildTransactionPage(returns: true);
    if (_selectedIndex == 4) {
      return ProfileScreen(
        showBackButton: false,
        showAppBar: false,
        onOpenEquipment: _openEquipmentList,
        onSignOut: _logout,
      );
    }
    return _buildHomePage(user, isDark);
  }

  Widget _buildTransactionPage({required bool returns}) {
    return RentalAdminView(
      key: ValueKey(returns ? 'staff-returns' : 'staff-rentals'),
      page: returns ? 'Returns' : 'Rentals',
      workspace: _workspace,
      onChanged: _refreshAfterChange,
      initialScanKind: _requestedScanKind,
      scanRequestId: _scanRequestId,
      onScanConsumed: _consumeScanRequest,
    );
  }

  Widget _buildHomePage(Map<String, dynamic> user, bool isDark) {
    final name = user['name']?.toString().trim() ?? '';
    final stats = _map(_dashboard['stats']);
    final pending = _countStatus('PENDING_ADMIN_APPROVAL');
    final approved = _countStatus('APPROVED');
    final active = _countStatus('ACTIVE');
    final inspections = _countStatus('RETURN_PENDING_INSPECTION');

    return RefreshIndicator(
      color: _AdminColors.orange,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
            name.isEmpty ? 'Staff counter' : 'Hi, $name',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _AdminColors.getInk(isDark),
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Handle rental handoffs and returns from your phone.',
            style: TextStyle(color: _AdminColors.getMuted(isDark)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF33271F) : const Color(0xFFFFF2E7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _AdminColors.orange.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: _AdminColors.orangeDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'COUNTER WORKFLOW',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFFFC79B)
                            : _AdminColors.orangeDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Scan, verify, hand off.',
                  style: TextStyle(
                    color: _AdminColors.getInk(isDark),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Use the phone camera for rental and equipment QR codes.',
                  style: TextStyle(color: _AdminColors.getMuted(isDark)),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _showScanOptions,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan QR'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _AdminColors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Rental activity',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: _CounterMetric(
                      label: 'Needs review',
                      value: '$pending',
                      icon: Icons.pending_actions_outlined,
                      tone: const Color(0xFFB56B1C),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _CounterMetric(
                      label: 'Awaiting handoff',
                      value: '$approved',
                      icon: Icons.outbound_outlined,
                      tone: const Color(0xFF477DA6),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _CounterMetric(
                      label: 'Currently rented',
                      value: '$active',
                      icon: Icons.sports_basketball_outlined,
                      tone: const Color(0xFF3B8C6E),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _CounterMetric(
                      label: 'Returns to inspect',
                      value: '$inspections',
                      icon: Icons.fact_check_outlined,
                      tone: const Color(0xFF7766A5),
                    ),
                  ),
                ],
              );
            },
          ),
          if (stats['available'] != null) ...[
            const SizedBox(height: 12),
            Text(
              '${stats['available']} items are currently available.',
              style: TextStyle(
                color: _AdminColors.getMuted(isDark),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Quick actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          _QuickActionCard(
            title: 'Rental requests',
            subtitle: 'Review requests, prepare units, and confirm handoffs.',
            count: pending + approved,
            icon: Icons.receipt_long_outlined,
            onTap: () => _selectTab(1),
          ),
          const SizedBox(height: 10),
          _QuickActionCard(
            title: 'Returns & inspections',
            subtitle: 'Receive equipment and finish return checks.',
            count: active + inspections,
            icon: Icons.assignment_return_outlined,
            onTap: () => _selectTab(3),
          ),
          const SizedBox(height: 12),
          Text(
            'Browse equipment and print labels here. For inventory setup, reports, rates, and staff settings, use the web admin workspace.',
            style: TextStyle(
              color: _AdminColors.getMuted(isDark),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = _map(_api.currentUser);
    final title = switch (_selectedIndex) {
      1 => 'Rentals',
      3 => 'Returns',
      4 => 'Profile',
      _ => 'Staff counter',
    };
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _AdminColors.getCanvas(isDark),
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            color: _AdminColors.getInk(isDark),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => unawaited(_refresh()),
            icon:
                Icon(Icons.refresh_rounded, color: _AdminColors.getInk(isDark)),
          ),
          RentalNotificationBell(color: _AdminColors.getInk(isDark)),
          PopupMenuButton<String>(
            tooltip: 'Staff account',
            onSelected: (value) {
              if (value == 'sign-out') unawaited(_logout());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'sign-out',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CircleAvatar(
                radius: 17,
                backgroundColor:
                    isDark ? const Color(0xFF3B1D0E) : const Color(0xFFFFE7D5),
                child: Text(
                  _initials(user['name']?.toString() ?? ''),
                  style: const TextStyle(
                    color: _AdminColors.orangeDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_connectionError.isNotEmpty)
            _ConnectionBanner(
              message: _connectionError,
              onRetry: () => unawaited(_refresh()),
            ),
          Expanded(child: _buildCurrentPage(user, isDark)),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          backgroundColor: scheme.surface,
          indicatorColor: scheme.primary.withValues(alpha: isDark ? .2 : .12),
          surfaceTintColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              )),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
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
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Rentals',
            ),
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_rounded),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.assignment_return_outlined),
              selectedIcon: Icon(Icons.assignment_return_rounded),
              label: 'Returns',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterMetric extends StatelessWidget {
  const _CounterMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 104,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _AdminColors.getCardBg(isDark),
        border: Border.all(color: _AdminColors.getLine(isDark)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: tone, size: 19),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  color: _AdminColors.getInk(isDark),
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _AdminColors.getMuted(isDark),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: _AdminColors.getCardBg(isDark),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: _AdminColors.getLine(isDark)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _AdminColors.orange.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _AdminColors.orangeDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _AdminColors.getInk(isDark),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _AdminColors.getMuted(isDark),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 14,
                backgroundColor: _AdminColors.getCanvas(isDark),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: _AdminColors.getInk(isDark),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: _AdminColors.getMuted(isDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: Color(0xFF9A5B00)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF7A4B00),
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _AdminColors {
  static const orange = Color(0xFFDF762D);
  static const orangeDark = Color(0xFFC45E1B);
  static const ink = Color(0xFF172333);
  static const muted = Color(0xFF708092);
  static const canvas = Color(0xFFF6F7F9);
  static const line = Color(0xFFE9EDF1);

  static Color getInk(bool isDark) => isDark ? const Color(0xFFF8FAFC) : ink;
  static Color getMuted(bool isDark) =>
      isDark ? const Color(0xFF94A3B8) : muted;
  static Color getCanvas(bool isDark) =>
      isDark ? const Color(0xFF0B1320) : canvas;
  static Color getCardBg(bool isDark) =>
      isDark ? const Color(0xFF131D2D) : Colors.white;
  static Color getLine(bool isDark) => isDark ? const Color(0xFF1E2C42) : line;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => row.map((key, value) => MapEntry('$key', value)))
        .toList()
    : <Map<String, dynamic>>[];

String _initials(String name) {
  final parts =
      name.trim().split(' ').where((part) => part.isNotEmpty).toList();
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
