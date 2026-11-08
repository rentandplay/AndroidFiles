import '../shared/support_chat_screen.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/glass_app_bar.dart';
import '../../services/server_clock.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_firestore_service.dart';
import '../../widgets/staff_ui.dart';
import '../../models/staff_scan.dart';
import '../shared/qr_capture_screen.dart';
import '../../widgets/notification_widgets.dart';
import 'equipment_list_screen.dart';
import 'maintenance_screen.dart';
import 'payments_screen.dart';
import 'rental_admin_view.dart';
import '../profile/profile_screen.dart';

/// Focused, adaptive staff workspace for counter operations.
///
/// Keeps the mobile tools needed at the counter: review rentals, scan QR codes,
/// hand off equipment, and process returns and unit maintenance with the same
/// signature brand styling as the customer experience.
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key, required this.onSignedOut, this.api});
  final VoidCallback onSignedOut;
  final AdminFirestoreService? api;

  @override
  Widget build(BuildContext context) => Theme(
        data: StaffTheme.from(Theme.of(context)),
        child: LiquidGlassScope(
            child: LiquidAmbientBackdrop(
                child: _StaffDashboard(onSignedOut: onSignedOut, api: api))),
      );
}

class _StaffDashboard extends StatefulWidget {
  const _StaffDashboard({required this.onSignedOut, this.api});
  final VoidCallback onSignedOut;
  final AdminFirestoreService? api;

  @override
  State<_StaffDashboard> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<_StaffDashboard>
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
  String _requestedStage = 'All';
  StaffScanResult? _requestedScan;
  bool _scannerOpen = false;
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
      final day = ServerClock.instance.now
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(0, 10);
      Map<String, dynamic> today = {};
      var todayError = '';
      final financeFuture = _api
          .getMap('/finance/summary?from=$day&to=$day&counter=true',
              forceRefresh: forceRefresh)
          .then((value) {
        today = value;
      }).catchError((Object _) {
        todayError = 'Today’s collection totals could not be refreshed.';
      });
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
    final workspaceRows = _rows(_workspace['transactions']);
    return workspaceRows.isNotEmpty
        ? workspaceRows
        : _rows(_dashboard['rentals']);
  }

  int _countStatus(String status) =>
      _rentals.where((row) => row['status'] == status).length;

  void _selectTab(int index, {String stage = 'All'}) {
    if (index == 2) {
      unawaited(_openScanner());
      return;
    }
    setState(() {
      _selectedIndex = index;
      _requestedStage = stage;
      _requestedScan = null;
    });
  }

  void _consumeScanRequest() {
    if (!mounted || _requestedScan == null) return;
    setState(() => _requestedScan = null);
  }

  void _openEquipmentList() {
    Navigator.of(context).push<void>(
      StaffPageRoute<void>(
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

  Future<void> _openScanner() async {
    if (_scannerOpen) return;
    _scannerOpen = true;
    try {
      final capture = await Navigator.of(context).push<StaffScanResult>(
        StaffPageRoute(builder: (_) => const QrCaptureScreen.staff()),
      );
      if (capture == null || !mounted) return;
      setState(() {
        _selectedIndex = capture.mode == StaffScanMode.equipment ? 3 : 1;
        _requestedStage = 'All';
        _requestedScan = capture;
        _scanRequestId++;
      });
    } finally {
      _scannerOpen = false;
    }
  }

  void _openMaintenance() {
    Navigator.of(context).push<void>(StaffPageRoute<void>(
      builder: (_) =>
          MaintenanceScreen(api: _api, onChanged: _refreshAfterChange),
    ));
  }

  Widget _buildCurrentPage(Map<String, dynamic> user, bool isDark) {
    if (_loading && _workspace.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
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
      initialStage: _requestedStage,
      workspace: _workspace,
      onChanged: _refreshAfterChange,
      initialCapture: _requestedScan,
      scanRequestId: _scanRequestId,
      onScanConsumed: _consumeScanRequest,
    );
  }

  Widget _buildHomePage(Map<String, dynamic> user, bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final stats = _map(_dashboard['stats']);
    final pending = _countStatus('PENDING_ADMIN_APPROVAL');
    final approved = _countStatus('APPROVED');
    final active = _countStatus('ACTIVE');
    final inspections = _countStatus('RETURN_PENDING_INSPECTION');
    final counter = _map(_today['counter']);
    final now = ServerClock.instance.now.toUtc();
    final overdue = _rentals.where((row) {
      final due = DateTime.tryParse('${row['due_at'] ?? ''}');
      return row['status'] == 'ACTIVE' && due != null && due.isBefore(now);
    }).length;
    final name = (user['name'] ?? 'team').toString().trim().split(' ').first;

    return LayoutBuilder(builder: (context, constraints) {
      final horizontal =
          constraints.maxWidth > 880 ? (constraints.maxWidth - 840) / 2 : 20.0;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text('Hi, ${name.isEmpty ? 'team' : name}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Here’s what’s happening at your counter.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (overdue > 0) ...[
              const SizedBox(height: 20),
              StaffActionTile(
                icon: Icons.assignment_late_outlined,
                title:
                    '$overdue overdue ${overdue == 1 ? 'rental' : 'rentals'}',
                subtitle: 'Follow up and receive returned equipment',
                urgent: true,
                onTap: () => _selectTab(3, stage: 'Overdue'),
              ),
            ],
            const SizedBox(height: 20),
            Material(
              color: StaffTheme.navy,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _openScanner,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Scan QR Code',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.4)),
                            const SizedBox(height: 5),
                            Text('Customer rentals & equipment',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: .75),
                                    fontSize: 13,
                                    height: 1.4)),
                          ])),
                      const SizedBox(width: 16),
                      Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFB787),
                              borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.qr_code_scanner_rounded,
                              size: 26, color: Color(0xFF42200C))),
                    ])),
              ),
            ),
            StaffSectionHeading('Rental activity',
                trailing: stats['available'] == null
                    ? null
                    : Text('${stats['available']} available',
                        style: Theme.of(context).textTheme.bodySmall)),
            LayoutBuilder(builder: (context, size) {
              final columns = size.maxWidth >= 640 ? 4 : 2;
              final width = (size.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(
                    width: width,
                    child: StaffMetric(
                        label: 'Needs review',
                        value: '$pending',
                        icon: Icons.pending_actions_rounded,
                        onTap: () => _selectTab(1, stage: 'Awaiting review'))),
                SizedBox(
                    width: width,
                    child: StaffMetric(
                        label: 'Awaiting handoff',
                        value: '$approved',
                        icon: Icons.outbound_outlined,
                        onTap: () => _selectTab(1,
                            stage: 'Approved · awaiting handoff'))),
                SizedBox(
                    width: width,
                    child: StaffMetric(
                        label: 'Currently rented',
                        value: '$active',
                        icon: Icons.sports_esports_outlined,
                        onTap: () => _selectTab(1, stage: 'In use'))),
                SizedBox(
                    width: width,
                    child: StaffMetric(
                        label: 'Returns to inspect',
                        value: '$inspections',
                        icon: Icons.fact_check_outlined,
                        onTap: () =>
                            _selectTab(3, stage: 'Inspection pending'))),
              ]);
            }),
            const StaffSectionHeading('Today’s collections'),
            StaffSurface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  if (_todayError.isNotEmpty)
                    Text(_todayError, style: TextStyle(color: scheme.error))
                  else ...[
                    Wrap(spacing: 32, runSpacing: 16, children: [
                      _collection(
                          'Cash', _map(_today['totals'])['cash_collections']),
                      _collection('QR payments',
                          _map(_today['totals'])['qr_collections']),
                    ]),
                    const SizedBox(height: 12),
                    Text('Due today: ${counter['due_today'] ?? '—'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ])),
            const StaffSectionHeading('Manage your workspace'),
            StaffActionTile(
                icon: Icons.inventory_2_outlined,
                title: 'Equipment & labels',
                subtitle: 'Availability, unit details and QR labels',
                onTap: _openEquipmentList),
            const SizedBox(height: 10),
            StaffActionTile(
                icon: Icons.build_outlined,
                title: 'Maintenance',
                subtitle: 'Repair tickets and equipment checks',
                onTap: _openMaintenance),
            const SizedBox(height: 10),
            StaffActionTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Payments & expenses',
                subtitle: 'Collections, balances and cash records',
                onTap: () => Navigator.push(context,
                    StaffPageRoute(builder: (_) => PaymentsScreen(api: _api)))),
          ],
        ),
      );
    });
  }

  Widget _collection(String label, dynamic amount) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
            amount == null
                ? '—'
                : '₱${(num.tryParse('$amount') ?? 0).toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleLarge),
      ]);

  @override
  Widget build(BuildContext context) {
    return _buildScaffold();
  }

  Widget _buildScaffold() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = _map(_api.currentUser);
    final title = switch (_selectedIndex) {
      1 => 'Rentals',
      3 => 'Returns',
      4 => 'Account',
      _ => 'Counter'
    };
    return Builder(
        builder: (staffContext) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: Scaffold(
                appBar: GlassAppBar(
                  automaticallyImplyLeading: false,
                  title: Text(title),
                  actions: [
                    IconButton(
                        tooltip: 'Refresh',
                        onPressed:
                            _loading ? null : () => unawaited(_refresh()),
                        icon: const Icon(Icons.refresh_rounded, size: 22)),
                    IconButton(tooltip: 'Customer messages', icon: const Icon(Icons.forum_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportInboxScreen(staff: true)))),
                    const RentalNotificationBell(),
                    IconButton(
                        tooltip: 'Staff account',
                        onPressed: () => _selectTab(4),
                        icon: CircleAvatar(
                            radius: 16,
                            backgroundColor: isDark
                                ? const Color(0xFF56301D)
                                : const Color(0xFFFFE8D9),
                            child: Text(
                                _initials(user['name']?.toString() ?? 'Staff'),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(staffContext)
                                        .colorScheme
                                        .primary)))),
                    const SizedBox(width: 8),
                  ],
                ),
                body: Column(children: [
                  if (_connectionError.isNotEmpty)
                    MaterialBanner(
                        content: Text(_connectionError),
                        leading: const Icon(Icons.cloud_off_outlined),
                        actions: [
                          TextButton(
                              onPressed: () => unawaited(_refresh()),
                              child: const Text('Retry'))
                        ]),
                  Expanded(child: _buildCurrentPage(user, isDark)),
                ]),
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                    child: LiquidGlassBottomNavBar(
                      selectedIndex: _selectedIndex,
                      onTabSelected: _selectTab,
                      tabs: const [
                        LiquidGlassTab(
                            label: 'Counter',
                            icon: Icons.space_dashboard_outlined,
                            activeIcon: Icons.space_dashboard_rounded),
                        LiquidGlassTab(
                            label: 'Rentals',
                            icon: Icons.receipt_long_outlined,
                            activeIcon: Icons.receipt_long_rounded),
                        LiquidGlassTab(
                            label: 'Scan', icon: Icons.qr_code_scanner_rounded),
                        LiquidGlassTab(
                            label: 'Returns',
                            icon: Icons.assignment_return_outlined,
                            activeIcon: Icons.assignment_return_rounded),
                        LiquidGlassTab(
                            label: 'Account',
                            icon: Icons.person_outline_rounded,
                            activeIcon: Icons.person_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ));
  }
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
