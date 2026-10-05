import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_firestore_service.dart';
import 'admin_module_view.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    this.initialAdminEmail,
  });

  final String? initialAdminEmail;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _dashboardItem = _AdminNavItem(
    'Dashboard',
    Icons.space_dashboard_outlined,
  );
  static const _reportsItem = _AdminNavItem('Reports', Icons.bar_chart_outlined);
  static const _settingsItem = _AdminNavItem('Settings', Icons.settings_outlined);
  static const _navGroups = <_AdminNavGroup>[
    _AdminNavGroup('Management', Icons.inventory_2_outlined, [
      _AdminNavItem('Equipment', Icons.inventory_2_outlined),
      _AdminNavItem('Customers', Icons.people_outline),
      _AdminNavItem('Rates & Fees', Icons.payments_outlined),
    ]),
    _AdminNavGroup('Transactions', Icons.sync_alt_rounded, [
      _AdminNavItem('Rentals', Icons.schedule_outlined),
      _AdminNavItem('Returns', Icons.assignment_return_outlined),
      _AdminNavItem('Transaction History', Icons.receipt_long_outlined),
    ]),
    _AdminNavGroup('Operations', Icons.build_outlined, [
      _AdminNavItem('Maintenance', Icons.build_outlined),
      _AdminNavItem('ESP32 / Verification', Icons.memory_outlined),
    ]),
  ];

  final _api = AdminFirestoreService.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _expandedNavGroups = <String, bool>{
    'Management': true,
    'Transactions': true,
    'Operations': true,
  };
  Timer? _refreshTimer;
  String _page = 'Dashboard';
  String _loginError = '';
  String _connectionError = '';
  bool _needsLogin = false;
  bool _loading = true;
  bool _submittingLogin = false;
  bool _refreshing = false;
  Map<String, dynamic> _dashboard = {};
  Map<String, dynamic> _workspace = {};
  Map<String, dynamic> _inventory = {};

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialAdminEmail ?? '';
    _loginError = '';
    _bootstrap();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!_api.hasSession) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _loading = false;
        });
      }
      return;
    }
    try {
      await _api.restoreAdminSession();
      await _loadWorkspace(withInventory: _page == 'Equipment');
      _startAutoRefresh();
    } on AdminApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _needsLogin = _isAuthFailure(error);
        _loginError = _needsLogin ? error.message : '';
        _connectionError = _needsLogin ? '' : error.message;
        _loading = false;
      });
    }
  }

  Future<void> _signIn() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _loginError = 'Enter your admin email and password.');
      return;
    }
    setState(() {
      _submittingLogin = true;
      _loginError = '';
    });
    try {
      await _api.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      _passwordController.clear();
      await _loadWorkspace(withInventory: _page == 'Equipment');
      _startAutoRefresh();
    } on AdminApiException catch (error) {
      if (mounted) setState(() => _loginError = error.message);
    } finally {
      if (mounted) setState(() => _submittingLogin = false);
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_needsLogin && _page != 'Settings') {
        _loadWorkspace(withInventory: _page == 'Equipment', quiet: true);
      }
    });
  }

  Future<void> _loadWorkspace({
    bool withInventory = false,
    bool quiet = false,
  }) async {
    if (_refreshing || !_api.hasSession) return;
    _refreshing = true;
    if (!quiet && mounted) {
      setState(() {
        _loading = true;
        _connectionError = '';
      });
    }
    try {
      final workspace = await _api.loadWorkspace();
      final dashboard = _api.dashboardFromWorkspace(workspace);
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _workspace = workspace;
        if (withInventory) _inventory = _api.inventoryFromWorkspace(workspace);
        _loading = false;
        _connectionError = '';
        _needsLogin = false;
      });
    } on AdminApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_isAuthFailure(error)) {
          _needsLogin = true;
          _loginError = error.message;
        } else {
          _connectionError = error.message;
        }
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refresh({bool withInventory = false}) =>
      _loadWorkspace(withInventory: withInventory || _page == 'Equipment');

  Future<void> _selectPage(String next) async {
    if (mounted) setState(() => _page = next);
    if (next == 'Equipment' && _inventory.isEmpty) {
      await _loadWorkspace(withInventory: true);
    }
  }

  Future<void> _logout() async {
    await _api.signOut();
    if (!mounted) return;
    setState(() {
      _needsLogin = true;
      _loading = false;
      _dashboard = {};
      _workspace = {};
      _inventory = {};
      _loginError = 'You have signed out of the admin workspace.';
      _connectionError = '';
    });
  }

  bool _isAuthFailure(AdminApiException error) =>
      error.statusCode == 401 ||
      (error.statusCode == 403 &&
          !error.message.startsWith('Firebase denied access.'));

  @override
  Widget build(BuildContext context) {
    if (_needsLogin) return _buildSignInPage();
    if (_loading && _dashboard.isEmpty) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: _AdminColors.orange)),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 920;
    final user = _map(_api.currentUser);
    final title = _page;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _AdminColors.getCanvas(isDark),
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: _AdminColors.getCardBg(isDark),
              child: _navigation(user, isDark, _closeDrawer),
            ),
      appBar: AppBar(
        backgroundColor: _AdminColors.getCardBg(isDark),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: isWide
            ? Padding(
                padding: const EdgeInsets.only(left: 18),
                child: _brandMark(),
              )
            : null,
        titleSpacing: isWide ? 16 : width < 480 ? 6 : null,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _AdminColors.getInk(isDark),
            fontWeight: FontWeight.w800,
            fontSize: width < 480 ? 17 : 19,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh workspace',
            onPressed: _loading ? null : () => _refresh(withInventory: true),
            icon: Icon(Icons.refresh_rounded, color: _AdminColors.getInk(isDark)),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => _showNotifications(context),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.notifications_none_rounded, color: _AdminColors.getInk(isDark)),
                if (_notificationCount > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _AdminColors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Admin account',
            onSelected: (value) {
              if (value == 'profile') _selectPage('Profile');
              if (value == 'admin-settings') _selectPage('Admin settings');
              if (value == 'logout') _logout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'profile', child: Text('Account profile')),
              PopupMenuItem(
                  value: 'admin-settings', child: Text('Admin settings')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: width < 480 ? 8 : 14),
              child: CircleAvatar(
                radius: 17,
                backgroundColor: isDark ? const Color(0xFF3B1D0E) : const Color(0xFFFFE7D5),
                child: Text(
                  _initials(user['name']?.toString() ?? 'Admin'),
                  style: const TextStyle(
                    color: _AdminColors.orangeDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            SizedBox(
              width: 256,
              child: Material(
                color: _AdminColors.getCardBg(isDark),
                child: _navigation(user, isDark, _closeDrawer),
              ),
            ),
          Expanded(
            child: Column(
              children: [
                if (_connectionError.isNotEmpty)
                  _ConnectionBanner(
                    message: _connectionError,
                    onRetry: () => _refresh(withInventory: true),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: _AdminColors.orange,
                    onRefresh: () => _refresh(withInventory: true),
                    child: SingleChildScrollView(
                      key: PageStorageKey<String>(_page),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        width < 480 ? 14 : 24,
                        20,
                        width < 480 ? 14 : 24,
                        36,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1320),
                          child: AdminModuleView(
                            page: _page,
                            dashboard: _dashboard,
                            workspace: _workspace,
                            inventory: _inventory,
                            loading: _loading,
                            onNavigate: _selectPage,
                            onRefresh: () => _refresh(withInventory: true),
                            onChanged: () => _refresh(withInventory: true),
                            onInventoryRefresh: () =>
                                _loadWorkspace(withInventory: true),
                            onSignOut: _logout,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _notificationCount {
    final stats = _map(_dashboard['stats']);
    return _number(stats['overdue']) + _list(_dashboard['pending']).length;
  }

  Widget _buildSignInPage() {
    return Scaffold(
      backgroundColor: _AdminColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _brandMark(inverse: true),
                      const SizedBox(width: 12),
                      const Text(
                        'OWNER / OPERATOR WORKSPACE',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          letterSpacing: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _AdminColors.orange.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: _AdminColors.orangeDark,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Welcome back!',
                            style: TextStyle(
                              color: _AdminColors.ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Sign in with an active admin account to manage Rent & Play.',
                            style: TextStyle(color: _AdminColors.muted),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(
                              labelText: 'Admin email',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _signIn(),
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_loginError.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              _loginError,
                              style: const TextStyle(
                                color: Color(0xFFB42318),
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: _submittingLogin ? null : _signIn,
                              style: FilledButton.styleFrom(
                                backgroundColor: _AdminColors.orange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _submittingLogin
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Sign in to your workspace',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Connected securely through Firebase',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _AdminColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Your account. Your equipment. Your workspace.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _closeDrawer() {
    _scaffoldKey.currentState?.closeDrawer();
  }

  Widget _navigation(
    Map<String, dynamic> user,
    bool isDark,
    VoidCallback closeDrawer,
  ) {
    final settings = _map(_workspace['settings']);
    final businessName = settings['business_name']?.toString() ?? 'Rent & Play';
    final businessLocation =
        settings['location']?.toString() ?? 'Los Baños, Laguna';
    final interrupted = _connectionError.isNotEmpty;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(children: [
              _brandMark(),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'rent&play',
                      style: TextStyle(
                        color: _AdminColors.getInk(isDark),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'RENTAL MANAGEMENT',
                      style: TextStyle(
                        color: _AdminColors.getMuted(isDark),
                        fontSize: 9,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A2638)
                    : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _AdminColors.getLine(isDark)),
              ),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _AdminColors.getCardBg(isDark),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: _AdminColors.getMuted(isDark),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _AdminColors.getInk(isDark),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        businessLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _AdminColors.getMuted(isDark),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          Divider(height: 1, color: _AdminColors.getLine(isDark)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                _navButton(_dashboardItem, closeDrawer, isDark),
                for (final group in _navGroups)
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: _AdminColors.orange.withValues(alpha: .08),
                      highlightColor:
                          _AdminColors.orange.withValues(alpha: .05),
                    ),
                    child: ExpansionTile(
                      key: PageStorageKey<String>(
                        'admin-navigation-${group.label}',
                      ),
                      initiallyExpanded:
                          _expandedNavGroups[group.label] ?? true,
                      onExpansionChanged: (expanded) {
                        _expandedNavGroups[group.label] = expanded;
                      },
                      leading: Icon(
                        group.icon,
                        size: 20,
                        color: _AdminColors.getMuted(isDark),
                      ),
                      title: Text(
                        group.label,
                        style: TextStyle(
                          color: _AdminColors.getInk(isDark),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(10, 0, 0, 6),
                      collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      iconColor: _AdminColors.getMuted(isDark),
                      collapsedIconColor: _AdminColors.getMuted(isDark),
                      children: [
                        for (final item in group.items)
                          _navButton(
                            item,
                            closeDrawer,
                            isDark,
                            nested: true,
                          ),
                      ],
                    ),
                  ),
                _navButton(_reportsItem, closeDrawer, isDark),
              ],
            ),
          ),
          Divider(height: 1, color: _AdminColors.getLine(isDark)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _navButton(_settingsItem, closeDrawer, isDark),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              leading: Icon(Icons.logout, color: _AdminColors.getMuted(isDark)),
              title: Text(
                'Sign out',
                style: TextStyle(
                  color: _AdminColors.getInk(isDark),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onTap: () {
                closeDrawer();
                _logout();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF14271F)
                    : const Color(0xFFF3F8F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: interrupted
                        ? const Color(0xFFCF4B4B)
                        : const Color(0xFF6D9A86),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        interrupted
                            ? 'Connection interrupted'
                            : 'Connected workspace',
                        style: TextStyle(
                          color: interrupted
                              ? const Color(0xFFB44040)
                              : const Color(0xFF527467),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _workspace.isEmpty
                            ? 'Waiting for database'
                            : 'Cloud Firestore records',
                        style: TextStyle(
                          color: _AdminColors.getMuted(isDark),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          ListTile(
            onTap: () {
              closeDrawer();
              _selectPage('Profile');
            },
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? const Color(0xFF3B1D0E) : const Color(0xFFFFE7D5),
              child: Text(
                _initials(user['name']?.toString() ?? 'Admin'),
                style: const TextStyle(
                  color: _AdminColors.orangeDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              user['name']?.toString() ?? 'Admin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _AdminColors.getInk(isDark),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            subtitle: Text(
              'Administrator',
              style: TextStyle(color: _AdminColors.getMuted(isDark), fontSize: 11),
            ),
            trailing: Icon(Icons.chevron_right,
                size: 19, color: _AdminColors.getMuted(isDark)),
          ),
        ],
      ),
    );
  }

  Widget _navButton(
    _AdminNavItem item,
    VoidCallback closeDrawer,
    bool isDark, {
    bool nested = false,
  }) {
    final selected = _page == item.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: nested ? 10 : 12),
        minLeadingWidth: 28,
        horizontalTitleGap: 10,
        minTileHeight: 48,
        selected: selected,
        selectedTileColor: isDark ? const Color(0xFF3B1D0E) : const Color(0xFFFFF1E8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          item.icon,
          color: selected ? _AdminColors.orangeDark : _AdminColors.getMuted(isDark),
          size: 20,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: selected ? _AdminColors.orangeDark : _AdminColors.getInk(isDark),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        onTap: () {
          closeDrawer();
          _selectPage(item.label);
        },
      ),
    );
  }

  Widget _brandMark({bool inverse = false}) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: inverse ? Colors.white : _AdminColors.navy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.sports_basketball_rounded,
        color: inverse ? _AdminColors.orange : Colors.white,
        size: 22,
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    final pending = _list(_dashboard['pending']);
    final rentals = _list(_dashboard['rentals']);
    final overdue =
        rentals.where((row) => row['displayStatus'] == 'Overdue').toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Alerts & notifications',
                style: TextStyle(
                  color: _AdminColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (overdue.isEmpty && pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    'You are all caught up. No overdue rentals or pending handoffs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _AdminColors.muted),
                  ),
                ),
              for (final rental in overdue.take(4))
                ListTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: _AdminColors.orange,
                  ),
                  title:
                      Text('${rental['item_name'] ?? 'Equipment'} is overdue'),
                  subtitle: Text(
                    '${rental['customer'] ?? 'Customer'} · ${rental['rental_code'] ?? ''}',
                  ),
                ),
              for (final request in pending.take(4))
                ListTile(
                  leading: const Icon(
                    Icons.memory_outlined,
                    color: _AdminColors.navy,
                  ),
                  title: Text(
                    '${request['transaction_type'] ?? 'Handoff'} needs terminal confirmation',
                  ),
                  subtitle: Text(
                    '${request['item_name'] ?? 'Equipment'} · ${request['customer'] ?? 'Customer'}',
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _selectPage('ESP32 / Verification');
                },
                child: const Text('Open verification activity'),
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: Color(0xFF9A5B00)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$message Showing the last successfully loaded records.',
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

class _AdminNavGroup {
  const _AdminNavGroup(this.label, this.icon, this.items);

  final String label;
  final IconData icon;
  final List<_AdminNavItem> items;
}

class _AdminNavItem {
  const _AdminNavItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _AdminColors {
  static const navy = Color(0xFF162A42);
  static const orange = Color(0xFFDF762D);
  static const orangeDark = Color(0xFFC45E1B);
  static const ink = Color(0xFF172333);
  static const muted = Color(0xFF708092);
  static const canvas = Color(0xFFF6F7F9);
  static const line = Color(0xFFE9EDF1);

  static Color getNavy(bool isDark) => isDark ? const Color(0xFF1E293B) : navy;
  static Color getInk(bool isDark) => isDark ? const Color(0xFFF8FAFC) : ink;
  static Color getMuted(bool isDark) => isDark ? const Color(0xFF94A3B8) : muted;
  static Color getCanvas(bool isDark) => isDark ? const Color(0xFF0B1320) : canvas;
  static Color getCardBg(bool isDark) => isDark ? const Color(0xFF131D2D) : Colors.white;
  static Color getLine(bool isDark) => isDark ? const Color(0xFF1E2C42) : line;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.map(_map).toList();
}

int _number(dynamic value) => int.tryParse('$value') ?? 0;

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}
