import '../../services/server_clock.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_firestore_service.dart';
import '../../widgets/brand_hero_header.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/premium_animations.dart';
import '../../widgets/rent_play_wordmark.dart';
import 'equipment_list_screen.dart';
import 'maintenance_screen.dart';
import 'payments_screen.dart';
import 'rental_admin_view.dart';
import '../profile/profile_screen.dart';

/// Luxury staff counter desk for the Android app.
///
/// Keeps the mobile tools needed at the counter: review rentals, scan QR codes,
/// hand off equipment, and process returns and unit maintenance with the same
/// signature brand styling as the customer experience.
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
  Map<String, dynamic> _today = {};
  String _todayError = '';
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
      final type = (event['event'] ?? '').toString();
      if (type == 'ready' || type.endsWith('.changed')) {
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
      final workspaceFuture = _api.loadWorkspace(forceRefresh: forceRefresh);
      final day = ServerClock.instance.now.toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10);
      Map<String, dynamic> today = {};
      var todayError = '';
      final financeFuture = _api.getMap('/finance/summary?from=$day&to=$day&counter=true', forceRefresh: forceRefresh).then((value) { today = value; }).catchError((Object _) { todayError = 'Today’s collection totals could not be refreshed.'; });
      final workspace = await workspaceFuture;
      await financeFuture;
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _today = today;
        _todayError = todayError;
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
          appBar: AppBar(title: const Text('Equipment Inventory')),
          body: EquipmentListScreen(
            items: _rows(_workspace['items']),
            onRefresh: _refresh,
            loadItems: () async =>
                _rows((await _api.getMap('/mobile/admin-workspace'))['items']),
          ),
        ),
      ),
    );
  }

  Future<void> _showScanOptions() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose what to scan',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select the code type to open the camera scanner.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 18),
              _ScanOptionTile(
                icon: Icons.qr_code_2_rounded,
                title: 'Customer rental QR',
                subtitle: 'Review a booking request or confirm equipment handoff.',
                onTap: () => Navigator.pop(sheetContext, 'BOOKING'),
              ),
              const SizedBox(height: 10),
              _ScanOptionTile(
                icon: Icons.inventory_2_outlined,
                title: 'Equipment barcode / QR',
                subtitle: 'Prepare a unit, receive returned gear, or inspect equipment.',
                onTap: () => Navigator.pop(sheetContext, 'INVENTORY'),
              ),
            ],
          ),
        ),
      ),
    );
    if (kind != null && mounted) _requestScan(kind);
  }

  void _openMaintenance() {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) =>
          MaintenanceScreen(api: _api, onChanged: _refreshAfterChange),
    ));
  }

  static const _staffTabs = [
    LiquidGlassTab(
      label: 'Counter',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
    ),
    LiquidGlassTab(
      label: 'Rentals',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
    ),
    LiquidGlassTab(
      label: 'Scan QR',
      icon: Icons.qr_code_scanner_rounded,
      activeIcon: Icons.qr_code_scanner_rounded,
    ),
    LiquidGlassTab(
      label: 'Returns',
      icon: Icons.assignment_return_outlined,
      activeIcon: Icons.assignment_return_rounded,
    ),
    LiquidGlassTab(
      label: 'Account',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

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

  Widget _buildStaffAvatarPod(Map<String, dynamic> user, bool isDark) {
    return PopupMenuButton<String>(
      tooltip: 'Staff account',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'sign-out') {
          unawaited(_logout());
        } else if (value == 'equipment') {
          _openEquipmentList();
        } else if (value == 'profile') {
          _selectTab(4);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user['name']?.toString() ?? 'Staff Operator',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                user['email']?.toString() ?? 'operator@rentandplay.local',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 20),
              SizedBox(width: 10),
              Text('Operator Profile'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'equipment',
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 20),
              SizedBox(width: 10),
              Text('Equipment Inventory'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'sign-out',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 20, color: Colors.red),
              SizedBox(width: 10),
              Text('Sign out',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8533), Color(0xFFE46618)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE46618).withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          _initials(user['name']?.toString() ?? ''),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
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
        padding: EdgeInsets.zero,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Today at a glance', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_todayError.isNotEmpty) Text(_todayError) else Wrap(spacing: 16, runSpacing: 8, children: [
                Text('On field: ${_map(_today['counter'])['active_units'] ?? '—'}'),
                Text('Due today: ${_map(_today['counter'])['due_today'] ?? '—'}'),
                Text('Overdue: ${_map(_today['counter'])['overdue'] ?? '—'}'),
                Text('Cash: ₱${_map(_today['totals'])['cash_collections'] ?? '—'}'),
                Text('QR: ₱${_map(_today['totals'])['qr_collections'] ?? '—'}'),
                Text('ESP32: ${_map(_today['counter'])['station_status'] ?? 'STANDBY'}'),
              ]),
            ]),
          )),
          // 1. Signature Midnight Navy Hero Header with Brand DNA
          ClipPath(
            clipper: const BrowseHeroBottomWaveClipper(),
            child: NavyOrangeHeroBackground(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Brand Wordmark + Operator Badge + Action Pods
                      Row(
                        children: [
                          const RentPlayWordmark(isLightOnDark: true),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF10B981),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'OPERATOR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          HeaderActionPod(
                            podBg: Colors.white.withValues(alpha: 0.14),
                            podBorder: Colors.white.withValues(alpha: 0.22),
                            iconColor: Colors.white,
                            icon: Icons.refresh_rounded,
                            tooltip: 'Refresh',
                            onTap: _loading ? null : () => unawaited(_refresh()),
                          ),
                          const SizedBox(width: 6),
                          const RentalNotificationBellPod(
                            podBg: Color(0x24FFFFFF),
                            podBorder: Color(0x38FFFFFF),
                            iconColor: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          _buildStaffAvatarPod(user, isDark),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        name.isEmpty ? 'Staff Counter Desk' : 'Hi, $name',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Handle rental handoffs, returns, and inventory checks.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Body Surface
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. Executive Counter Workflow Hero Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF14233D), const Color(0xFF0C1728)]
                          : [const Color(0xFF0F1E36), const Color(0xFF081222)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF071224).withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: const Color(0xFFDF762D).withValues(alpha: 0.28),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDF762D).withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFDF762D).withValues(alpha: 0.40),
                              ),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Color(0xFFFF9E58),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'COUNTER WORKFLOW',
                            style: TextStyle(
                              color: Color(0xFFFF9E58),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Scan, verify, hand off.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use the camera for customer rental booking QR codes or equipment barcodes.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      PremiumPressable(
                        onTap: _showScanOptions,
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF8533), Color(0xFFE46618)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE46618).withValues(alpha: 0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_scanner_rounded,
                                  size: 20, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'Scan QR Code',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // B. Rental Activity Metric Grid
                Row(
                  children: [
                    Text(
                      'Rental activity',
                      style: TextStyle(
                        color: _AdminColors.getInk(isDark),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    if (stats['available'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${stats['available']} available',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
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
                            icon: Icons.pending_actions_rounded,
                            tone: const Color(0xFFF59E0B),
                            onTap: () => _selectTab(1),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _CounterMetric(
                            label: 'Awaiting handoff',
                            value: '$approved',
                            icon: Icons.outbound_rounded,
                            tone: const Color(0xFF0EA5E9),
                            onTap: () => _selectTab(1),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _CounterMetric(
                            label: 'Currently rented',
                            value: '$active',
                            icon: Icons.sports_basketball_rounded,
                            tone: const Color(0xFF10B981),
                            onTap: () => _selectTab(3),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _CounterMetric(
                            label: 'Returns to inspect',
                            value: '$inspections',
                            icon: Icons.fact_check_rounded,
                            tone: const Color(0xFF8B5CF6),
                            onTap: () => _selectTab(3),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),

                // C. Quick Action Cards
                Text(
                  'Quick actions',
                  style: TextStyle(
                    color: _AdminColors.getInk(isDark),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 12),
                _QuickActionCard(
                  title: 'Rental requests',
                  subtitle:
                      'Review requests, prepare units, and confirm handoffs.',
                  count: pending + approved,
                  icon: Icons.receipt_long_rounded,
                  onTap: () => _selectTab(1),
                ),
                const SizedBox(height: 10),
                _QuickActionCard(
                  title: 'Returns & inspections',
                  subtitle: 'Receive equipment and finish return checks.',
                  count: active + inspections,
                  icon: Icons.assignment_return_rounded,
                  onTap: () => _selectTab(3),
                ),
                const SizedBox(height: 22),

                // D. Management & Equipment Tools
                Text(
                  'Operations & tools',
                  style: TextStyle(
                    color: _AdminColors.getInk(isDark),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryActionCard(
                        title: 'Maintenance',
                        subtitle: 'Repairs & units',
                        icon: Icons.build_circle_outlined,
                        onTap: _openMaintenance,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SecondaryActionCard(
                        title: 'Payments',
                        subtitle: 'Logs & expenses',
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PaymentsScreen(api: _api)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _SecondaryActionCard(
                  title: 'Equipment Catalog & Labels',
                  subtitle:
                      'Browse all inventory, inspect availability, and print QR codes.',
                  icon: Icons.qr_code_2_rounded,
                  onTap: _openEquipmentList,
                ),
              ],
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
      4 => 'Account Profile',
      _ => 'Staff Counter',
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        extendBody: true,
        backgroundColor: _AdminColors.getCanvas(isDark),
        appBar: _selectedIndex == 0
            ? null
            : AppBar(
                backgroundColor:
                    isDark ? const Color(0xFF030814) : const Color(0xFF071224),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                actions: [
                  HeaderActionPod(
                    podBg: Colors.white.withValues(alpha: 0.14),
                    podBorder: Colors.white.withValues(alpha: 0.22),
                    iconColor: Colors.white,
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    onTap: _loading ? null : () => unawaited(_refresh()),
                  ),
                  const SizedBox(width: 6),
                  const RentalNotificationBellPod(
                    podBg: Color(0x24FFFFFF),
                    podBorder: Color(0x38FFFFFF),
                    iconColor: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  _buildStaffAvatarPod(user, isDark),
                  const SizedBox(width: 8),
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: LiquidGlassBottomNavBar(
              selectedIndex: _selectedIndex,
              tabs: _staffTabs,
              onTabSelected: _selectTab,
            ),
          ),
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
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumPressable(
      onTap: onTap,
      child: Container(
        height: 108,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _AdminColors.getCardBg(isDark),
          border: Border.all(
            color: tone.withValues(alpha: isDark ? 0.30 : 0.22),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(alpha: isDark ? 0.08 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: tone, size: 19),
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    color: _AdminColors.getInk(isDark),
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.5,
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
    return PremiumPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _AdminColors.getCardBg(isDark),
          border: Border.all(color: _AdminColors.getLine(isDark)),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF8533),
                    Color(0xFFE46618),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE46618).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _AdminColors.getInk(isDark),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _AdminColors.getMuted(isDark),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFDF762D).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFFDF762D),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                color: _AdminColors.getMuted(isDark), size: 20),
          ],
        ),
      ),
    );
  }
}

class _SecondaryActionCard extends StatelessWidget {
  const _SecondaryActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _AdminColors.getCardBg(isDark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AdminColors.getLine(isDark)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFDF762D).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFDF762D), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _AdminColors.getInk(isDark),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
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
          ],
        ),
      ),
    );
  }
}

class _ScanOptionTile extends StatelessWidget {
  const _ScanOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PremiumPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _AdminColors.getCardBg(isDark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AdminColors.getLine(isDark)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDF762D).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded,
                  color: Color(0xFFDF762D), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _AdminColors.getInk(isDark),
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: _AdminColors.getMuted(isDark),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: _AdminColors.getMuted(isDark), size: 20),
          ],
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
  static const canvas = Color(0xFFF6F8FC);
  static const line = Color(0xFFE2E8F0);

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
