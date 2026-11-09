import '../../widgets/live_business_settings.dart';
import '../../widgets/staff_ui.dart';
import '../../services/business_settings.dart';
import '../../widgets/liquid_glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../auth/id_verification_screen.dart';
import '../auth/login_screen.dart';
import '../shared/terms_dialog.dart';
import '../../widgets/mobile_controls.dart';
import '../../widgets/glass_app_bar.dart';
import 'settings_screen.dart';
import '../shared/support_chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.showBackButton = true,
    this.showAppBar = true,
    this.onOpenEquipment,
    this.onSignOut,
    this.onViewRentals,
    this.onViewHistory,
  });

  final bool showBackButton;
  final bool showAppBar;
  final VoidCallback? onOpenEquipment;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onViewRentals;
  final VoidCallback? onViewHistory;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedTab = 'My profile';
  bool _isEditing = false;
  bool _isLoading = false;
  Uint8List? _imageBytes;
  String? _profileImageUrl;
  late Future<UserModel?> _profileFuture;
  String? _profileUserId;

  int _activeRentalsCount = 0;
  int _historyRentalsCount = 0;

  @override
  void initState() {
    super.initState();
    _profileUserId = context.read<AuthService>().currentUser?.uid;
    _profileFuture = _loadUserData();
    _loadRentalStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = Provider.of<AuthService>(context).currentUser?.uid;
    if (userId == _profileUserId) return;
    _profileUserId = userId;
    _isEditing = false;
    _isLoading = false;
    _imageBytes = null;
    _profileImageUrl = null;
    _nameController.clear();
    _phoneController.clear();
    _activeRentalsCount = 0;
    _historyRentalsCount = 0;
    _profileFuture = _loadUserData();
    _loadRentalStats();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<UserModel?> _loadUserData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final requestedUserId = user?.uid;
    final userModel = await authService.getCurrentUserModel();
    if (mounted && requestedUserId == _profileUserId) {
      final modelPhotoUrl = userModel?.profileImageUrl?.trim() ?? '';
      final authPhotoUrl = user?.photoURL?.trim() ?? '';
      final resolvedUrl = modelPhotoUrl.startsWith('http')
          ? modelPhotoUrl
          : (authPhotoUrl.startsWith('http') ? authPhotoUrl : null);
      setState(() {
        _nameController.text = userModel?.name.trim().isNotEmpty == true
            ? userModel!.name.trim()
            : user?.displayName ?? '';
        _phoneController.text = userModel?.phone ?? '';
        _profileImageUrl = resolvedUrl;
      });
    }
    return userModel;
  }

  Future<void> _loadRentalStats() async {
    try {
      final user = Provider.of<AuthService>(context, listen: false).currentUser;
      if (user == null) return;
      final rentals = await MobileApiService.instance.listRentals();
      if (!mounted) return;
      setState(() {
        _activeRentalsCount = rentals.where((r) => r.isOpen).length;
        _historyRentalsCount = rentals.where((r) => !r.isOpen).length;
      });
    } catch (_) {}
  }

  Future<void> _openSettings(UserModel? userModel) async {
    Widget builder(BuildContext context) =>
        SettingsScreen(userModel: userModel, onSignOut: widget.onSignOut);
    await Navigator.push(
        context,
        userModel?.isStaff == true
            ? StaffPageRoute<void>(builder: builder)
            : MaterialPageRoute<void>(builder: builder));
    if (mounted) {
      setState(() {
        _profileFuture = _loadUserData();
      });
      _loadRentalStats();
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);

      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      setState(() => _isLoading = true);

      final isPng = pickedFile.path.toLowerCase().endsWith('.png');
      final url = await MobileApiService.instance.uploadProfilePicture(
        uid: user.uid,
        bytes: bytes,
        contentType: isPng ? 'image/png' : 'image/jpeg',
      );

      await authService.updateProfileImageUrl(url);
      final currentModel = await _profileFuture;

      if (!mounted) return;
      setState(() {
        _profileImageUrl = url;
        if (currentModel != null) {
          _profileFuture = SynchronousFuture<UserModel?>(
            currentModel.copyWith(profileImageUrl: url),
          );
        }
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture saved to Supabase successfully!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload profile picture: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name with at least 2 letters.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final updatedProfile = await authService.updateCustomerProfile(
        name: name,
        phone: _phoneController.text,
        profileImageUrl: _profileImageUrl,
      );

      if (!mounted || updatedProfile.uid != _profileUserId) return;
      final mergedProfile = (_profileImageUrl != null &&
              _profileImageUrl!.isNotEmpty &&
              (updatedProfile.profileImageUrl ?? '').isEmpty)
          ? updatedProfile.copyWith(profileImageUrl: _profileImageUrl)
          : updatedProfile;
      setState(() {
        _nameController.text = mergedProfile.name;
        _phoneController.text = mergedProfile.phone;
        if ((mergedProfile.profileImageUrl ?? '').startsWith('http')) {
          _profileImageUrl = mergedProfile.profileImageUrl;
        }
        _profileFuture = SynchronousFuture<UserModel?>(mergedProfile);
        _isEditing = false;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update profile: $e')),
      );
    }
  }

  Future<void> _confirmSignOut(AuthService authService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime to track rentals.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.onSignOut != null) {
      await widget.onSignOut!();
      return;
    }
    await authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = authService.currentUser;

    final isDark = themeProvider.isDarkMode ||
        Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D131D) : const Color(0xFFFBF8F5);
    final cardBg = isDark ? const Color(0xFF162030) : const Color(0xFFFFFDFB);
    final cardBorder =
        isDark ? const Color(0xFF243248) : const Color(0xFFEAE2D8);
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputFill =
        isDark ? const Color(0xFF1A2638) : const Color(0xFFF8FAFC);
    final topPadding = widget.showAppBar
        ? MediaQuery.of(context).padding.top + kToolbarHeight
        : 0.0;

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: widget.showAppBar,
      appBar: widget.showAppBar
          ? GlassAppBar(
              automaticallyImplyLeading: widget.showBackButton,
              leading: widget.showBackButton
                  ? HeaderActionPod(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.pop(context),
                    )
                  : null,
              titleText: 'Profile',
              actions: [
                if (user != null) ...[
                  HeaderActionPod(
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: 'Rental support',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SupportInboxScreen()),
                    ),
                  ),
                  const RentalNotificationBellPod(),
                ],
                HeaderActionPod(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onTap: () async {
                    final userModel = await _profileFuture;
                    if (!context.mounted) return;
                    _openSettings(userModel);
                  },
                ),
              ],
            )
          : null,
      body: LiquidAmbientBackdrop(
        child: FutureBuilder<UserModel?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 32, color: textSecondary),
                      const SizedBox(height: 12),
                      Text('Could not load your profile.',
                          style: TextStyle(color: textPrimary),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            setState(() => _profileFuture = _loadUserData()),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final userModel = snapshot.data;
            final isAdmin = userModel?.isStaff ?? false;
            if (isAdmin) {
              return _buildStaffAccount(
                  userModel,
                  user,
                  authService,
                  themeProvider,
                  isDark,
                  cardBg,
                  cardBorder,
                  textPrimary,
                  textSecondary,
                  inputFill,
                  topPadding);
            }

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, topPadding + 12, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user == null) ...[
                    _buildGuestProfileCard(
                        cardBg, cardBorder, textPrimary, textSecondary),
                  ] else ...[
                    _buildCustomerProfileCard(
                      userModel,
                      user,
                      isDark,
                      cardBg,
                      cardBorder,
                      textPrimary,
                      textSecondary,
                      authService,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStaffAccount(
    UserModel? model,
    dynamic user,
    AuthService auth,
    ThemeProvider theme,
    bool dark,
    Color card,
    Color border,
    Color ink,
    Color muted,
    Color fill,
    double topPadding,
  ) {
    final section =
        ['Business', 'Appearance', 'Account & security'].contains(_selectedTab)
            ? _selectedTab
            : 'Overview';
    return PopScope(
        canPop: section == 'Overview',
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leaveStaffSection(model);
        },
        child: SizedBox.expand(
            child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: LayoutBuilder(builder: (context, size) {
            final horizontal =
                size.maxWidth > 880 ? (size.maxWidth - 840) / 2 : 20.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                  horizontal, topPadding + 20, horizontal, 28),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (section != 'Overview') ...[
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              _leaveStaffSection(model);
                            },
                            icon:
                                const Icon(Icons.arrow_back_rounded, size: 18),
                            label: const Text('Account overview'),
                          )),
                      const SizedBox(height: 12),
                      if (section == 'Business')
                        _buildBusinessTabCard(
                            dark, card, border, ink, muted, fill,
                            canEdit: model?.role == 'OWNER')
                      else if (section == 'Appearance')
                        _buildAppearanceTabCard(
                            theme, dark, card, border, ink, muted)
                      else
                        _buildUsersAccountTabCard(
                            model,
                            user,
                            model?.role ?? 'OPERATOR',
                            dark,
                            card,
                            border,
                            ink,
                            muted,
                            fill),
                    ] else ...[
                      StaffSurface(
                          color: StaffTheme.navy,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('YOUR WORKSPACE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFFFC59F))),
                                const SizedBox(height: 16),
                                Text(model?.name ?? 'Staff member',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -.5)),
                                const SizedBox(height: 5),
                                Text(user?.email ?? '',
                                    style: const TextStyle(
                                        color: Color(0xFFCDDAE8),
                                        fontSize: 13)),
                                const SizedBox(height: 14),
                                Text(
                                    model?.role == 'OWNER'
                                        ? 'Owner access'
                                        : 'Operator access',
                                    style: const TextStyle(
                                        color: Color(0xFFFFC59F),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ])),
                      const StaffSectionHeading('Workspace'),
                      StaffActionTile(
                          icon: Icons.storefront_outlined,
                          title: 'Business details',
                          subtitle: 'Store information and operating hours',
                          onTap: () =>
                              setState(() => _selectedTab = 'Business')),
                      if (widget.onOpenEquipment != null) ...[
                        const SizedBox(height: 10),
                        StaffActionTile(
                            icon: Icons.inventory_2_outlined,
                            title: 'Equipment & labels',
                            subtitle: 'Browse units and print QR labels',
                            onTap: widget.onOpenEquipment!),
                      ],
                      const StaffSectionHeading('Personal settings'),
                      StaffActionTile(
                          icon: Icons.person_outline_rounded,
                          title: 'Your profile',
                          subtitle: 'Name, contact details and profile photo',
                          onTap: () => setState(
                              () => _selectedTab = 'Account & security')),
                      const SizedBox(height: 10),
                      StaffActionTile(
                          icon: Icons.palette_outlined,
                          title: 'Appearance',
                          subtitle:
                              dark ? 'Dark appearance' : 'Light appearance',
                          onTap: () =>
                              setState(() => _selectedTab = 'Appearance')),
                      const SizedBox(height: 10),
                      StaffActionTile(
                          icon: Icons.tune_rounded,
                          title: 'Settings & security',
                          subtitle:
                              'Notifications, password and account access',
                          onTap: () => _openSettings(model)),
                      const SizedBox(height: 28),
                      OutlinedButton.icon(
                        key: const ValueKey('profile-sign-out'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error),
                        onPressed:
                            _isLoading ? null : () => _confirmSignOut(auth),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ]),
            );
          }),
        )));
  }

  void _leaveStaffSection(UserModel? model) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedTab = 'Overview';
      _isEditing = false;
      _nameController.text = model?.name ?? '';
      _phoneController.text = model?.phone ?? '';
    });
  }

  // --- BUSINESS TAB CARD ---
  Widget _buildBusinessTabCard(bool isDark, Color cardBg, Color cardBorder,
      Color textPrimary, Color textSecondary, Color inputFill,
      {required bool canEdit}) {
    return LiveBusinessSettings(builder: (context, settings) {
      if (!settings.loaded) {
        return Text(
            settings.error.isEmpty ? 'Loading store details…' : settings.error);
      }
      final values = settings.values;
      return StaffSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Business details',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('The store information shared across your workspace.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 24),
        _businessDetail('Business name', values['business_name']),
        _businessDetail('Location', values['location']),
        _businessDetail('Operating hours',
            '${formatBusinessTime(values['opens_at'])} – ${formatBusinessTime(values['closes_at'])}'),
        _businessDetail('Currency', values['currency'] ?? 'PHP'),
        _businessDetail('Timezone', values['timezone'] ?? 'Asia/Manila'),
        _businessDetail('Late grace period',
            '${values['default_late_grace_hours'] ?? 0} hours'),
        const SizedBox(height: 8),
        const Text(
            'Manage business details, rates and printer layouts in the web dashboard.',
            style: TextStyle(fontSize: 13, height: 1.5)),
        if (settings.error.isNotEmpty)
          Text(settings.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]));
    });
  }

  // --- APPEARANCE TAB CARD ---
  Widget _buildAppearanceTabCard(
    ThemeProvider themeProvider,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'APPEARANCE & THEME',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF57C00),
                letterSpacing: 1.0),
          ),
          const SizedBox(height: 4),
          Text(
            'App appearance',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          const SizedBox(height: 5),
          Text(
            'Choose a theme that feels comfortable in your surroundings. Your choice updates the app right away.',
            style: TextStyle(color: textSecondary, height: 1.4, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Material(
              color: Colors.transparent,
              child: SwitchListTile(
                secondary: Icon(
                  themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: const Color(0xFFF57C00),
                ),
                title: Text('Use dark appearance',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: textPrimary)),
                subtitle: Text(
                  themeProvider.isDarkMode
                      ? 'Dark appearance is enabled'
                      : 'Light appearance is enabled',
                  style: TextStyle(color: textSecondary),
                ),
                value: themeProvider.isDarkMode,
                onChanged: (val) => themeProvider.toggleTheme(val),
              )),
        ],
      ),
    );
  }

  Widget _businessDetail(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
              value?.toString().trim().isNotEmpty == true
                  ? '$value'
                  : 'Not set',
              style: Theme.of(context).textTheme.titleMedium),
        ]),
      );

  Widget _buildGuestProfileCard(Color cardBg, Color cardBorder,
          Color textPrimary, Color textSecondary) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: .1),
              child: Icon(Icons.person_outline_rounded,
                  size: 34, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text('Make rentals yours',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text(
              'Sign in to manage your profile, track requests, and keep your rental history in one place.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Sign in'),
            ),
          ],
        ),
      );

  Widget _buildCustomerProfileCard(
    UserModel? userModel,
    dynamic user,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
    AuthService authService,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header Card (Avatar, Name, Email, Verification)
        _buildCustomerHeaderCard(
          userModel,
          user,
          isDark,
          cardBg,
          cardBorder,
          textPrimary,
          textSecondary,
        ),

        const SizedBox(height: 12),

        // 2. Activity / Rental Stats (Active, History, Joined)
        _buildCustomerStatsRow(
          userModel,
          isDark,
          cardBg,
          cardBorder,
          textPrimary,
          textSecondary,
        ),

        // 3. Personal Information
        _sectionHeader('PERSONAL INFORMATION', textSecondary),
        _buildInfoCard(
          userModel: userModel,
          user: user,
          isDark: isDark,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),

        // 4. Quick Shortcuts
        _sectionHeader('QUICK SHORTCUTS', textSecondary),
        _buildShortcutsCard(
          userModel: userModel,
          isDark: isDark,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),

        // 5. Integrated Sign Out Button
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 24),
          child: OutlinedButton.icon(
            key: const ValueKey('profile-sign-out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              backgroundColor: cardBg,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              side: BorderSide(
                color:
                    Theme.of(context).colorScheme.error.withValues(alpha: .35),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _isLoading ? null : () => _confirmSignOut(authService),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text(
              'Sign out',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  ImageProvider? _resolveAvatarImage(UserModel? userModel, dynamic user) {
    if (_imageBytes != null) {
      return MemoryImage(_imageBytes!);
    }
    final candidates = <String?>[
      _profileImageUrl,
      userModel?.profileImageUrl,
      user?.photoURL?.toString(),
    ];
    for (final raw in candidates) {
      final url = raw?.trim() ?? '';
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return NetworkImage(url);
      }
    }
    return null;
  }

  Widget _buildCustomerHeaderCard(
    UserModel? userModel,
    dynamic user,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    final name = _profileValue(userModel?.name.trim().isNotEmpty == true
        ? userModel!.name
        : user?.displayName?.toString());
    final email = _profileValue(userModel?.email.trim().isNotEmpty == true
        ? userModel!.email
        : user?.email?.toString());
    final avatarImage = _resolveAvatarImage(userModel, user);

    return GlassCard(
      key: const ValueKey('customer-profile-card'),
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Tooltip(
            message: 'Change profile photo',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: _isLoading ? null : _pickAndUploadImage,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: isDark
                              ? const Color(0xFF1E2C42)
                              : const Color(0xFFF1F5F9),
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? Icon(Icons.person_rounded,
                                  size: 32, color: textSecondary)
                              : null,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: mobileAccentText(context),
                            shape: BoxShape.circle,
                            border: Border.all(color: cardBg, width: 2),
                          ),
                          child: _isLoading
                              ? Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isDark
                                        ? const Color(0xFF0F172A)
                                        : Colors.white,
                                  ),
                                )
                              : Icon(
                                  Icons.camera_alt_outlined,
                                  size: 13,
                                  color: isDark
                                      ? const Color(0xFF0F172A)
                                      : Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: name == 'Not set' ? textSecondary : textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                _buildVerificationBadge(userModel, isDark),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const ValueKey('profile-edit'),
            tooltip: _isEditing ? 'Close editor' : 'Edit profile',
            onPressed: _isLoading
                ? null
                : () => setState(() => _isEditing = !_isEditing),
            color: mobileAccentText(context),
            icon: Icon(
              _isEditing ? Icons.close_rounded : Icons.edit_outlined,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge(UserModel? userModel, bool isDark) {
    final isVerified = userModel?.hasAcknowledgedIdRequirement == true;
    if (isVerified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF132E1D) : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF2E7D32) : const Color(0xFFA5D6A7),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 13, color: Color(0xFF2E7D32)),
            SizedBox(width: 4),
            Text(
              'Verified ID',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IdVerificationScreen(userModel: userModel),
          ),
        ).then((_) {
          if (mounted) {
            setState(() => _profileFuture = _loadUserData());
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2F2108) : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFFD97706) : const Color(0xFFFDBA74),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 13, color: Color(0xFFD97706)),
            SizedBox(width: 4),
            Text(
              'Verify ID',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD97706),
              ),
            ),
            SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded,
                size: 13, color: Color(0xFFD97706)),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerStatsRow(
    UserModel? userModel,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFFDF762D),
            iconBg: isDark ? const Color(0xFF332015) : const Color(0xFFFEF3EA),
            value: _activeRentalsCount.toString(),
            label: 'Active',
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: widget.onViewRentals,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            icon: Icons.history_rounded,
            iconColor: const Color(0xFF2563EB),
            iconBg: isDark ? const Color(0xFF13233E) : const Color(0xFFEFF6FF),
            value: _historyRentalsCount.toString(),
            label: 'History',
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: widget.onViewHistory,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            icon: Icons.calendar_month_outlined,
            iconColor: const Color(0xFF0D9488),
            iconBg: isDark ? const Color(0xFF102D2A) : const Color(0xFFF0FDFA),
            value: _memberSinceText(userModel),
            label: 'Joined',
            cardBg: cardBg,
            cardBorder: cardBorder,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: null,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String value,
    required String label,
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _memberSinceText(UserModel? userModel) {
    if (userModel?.createdAt == null) return 'Recent';
    try {
      return DateFormat('MMM yyyy', 'en').format(userModel!.createdAt!);
    } catch (_) {
      return 'Recent';
    }
  }

  Widget _buildInfoCard({
    required UserModel? userModel,
    required dynamic user,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final name = _profileValue(userModel?.name.trim().isNotEmpty == true
        ? userModel!.name
        : user?.displayName?.toString());
    final email = _profileValue(userModel?.email.trim().isNotEmpty == true
        ? userModel!.email
        : user?.email?.toString());
    final phone = _profileValue(userModel?.phone);

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: _isEditing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  enabled: !_isLoading,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _phoneController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Phone number (optional)',
                    hintText: 'e.g. 0917 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: textPrimary,
                        ),
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                  _nameController.text =
                                      userModel?.name.trim().isNotEmpty == true
                                          ? userModel!.name
                                          : user?.displayName?.toString() ?? '';
                                  _phoneController.text =
                                      userModel?.phone ?? '';
                                  _isEditing = false;
                                }),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          backgroundColor: mobileAccentText(context),
                          foregroundColor:
                              isDark ? const Color(0xFF0F172A) : Colors.white,
                        ),
                        onPressed: _isLoading ? null : _saveProfile,
                        icon: _isLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isDark
                                      ? const Color(0xFF0F172A)
                                      : Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                _infoTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Full Name',
                  value: name,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
                Divider(height: 20, indent: 50, color: cardBorder),
                _infoTile(
                  icon: Icons.phone_outlined,
                  label: 'Phone Number',
                  value: phone,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
                Divider(height: 20, indent: 50, color: cardBorder),
                _infoTile(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email Address',
                  value: email,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
                Divider(height: 20, indent: 50, color: cardBorder),
                _infoTile(
                  icon: Icons.badge_outlined,
                  label: 'Account Role',
                  value: 'Customer',
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              ],
            ),
    );
  }

  Widget _buildShortcutsCard({
    required UserModel? userModel,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return GlassCard(
      borderRadius: 18,
      child: Column(
        children: [
          _shortcutTile(
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFFDF762D),
            iconBg: isDark ? const Color(0xFF332015) : const Color(0xFFFEF3EA),
            title: 'My Active Rentals',
            subtitle: 'View ongoing timers & return stations',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: widget.onViewRentals,
          ),
          Divider(height: 1, indent: 64, color: cardBorder),
          _shortcutTile(
            icon: Icons.receipt_long_outlined,
            iconColor: const Color(0xFF2563EB),
            iconBg: isDark ? const Color(0xFF13233E) : const Color(0xFFEFF6FF),
            title: 'Rental History & Receipts',
            subtitle: 'Past rentals, payments, and return logs',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: widget.onViewHistory,
          ),
          Divider(height: 1, indent: 64, color: cardBorder),
          _shortcutTile(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: const Color(0xFF0284C7),
            iconBg: isDark ? const Color(0xFF0B243B) : const Color(0xFFE0F2FE),
            title: 'Rental Support & Chat',
            subtitle: 'Ask about bookings, equipment, or get help',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupportInboxScreen()),
            ),
          ),
          Divider(height: 1, indent: 64, color: cardBorder),
          _shortcutTile(
            icon: Icons.settings_outlined,
            iconColor: const Color(0xFF7C3AED),
            iconBg: isDark ? const Color(0xFF22163D) : const Color(0xFFF5F3FF),
            title: 'Settings & Preferences',
            subtitle: 'Dark mode, push alerts, password & ID',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: () => _openSettings(userModel),
          ),
          Divider(height: 1, indent: 64, color: cardBorder),
          _shortcutTile(
            icon: Icons.description_outlined,
            iconColor: const Color(0xFF0D9488),
            iconBg: isDark ? const Color(0xFF102D2A) : const Color(0xFFF0FDFA),
            title: 'Terms & Conditions',
            subtitle: 'Rental guidelines and safety policies',
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            onTap: () => TermsDialog.show(context, readOnly: true),
          ),
        ],
      ),
    );
  }

  Widget _shortcutTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required Color textPrimary,
    required Color textSecondary,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: textSecondary),
      ),
      trailing:
          Icon(Icons.chevron_right_rounded, color: textSecondary, size: 20),
      onTap: onTap,
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2838) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: textSecondary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: value == 'Not set' ? textSecondary : textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  String _profileValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not set';

  // --- USERS & ACCOUNT TAB CARD ---
  Widget _buildUsersAccountTabCard(
    UserModel? userModel,
    dynamic user,
    String role,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
    Color inputFill,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor:
                    isDark ? const Color(0xFF1E2C42) : Colors.grey.shade200,
                backgroundImage: _resolveAvatarImage(userModel, user),
                child: _resolveAvatarImage(userModel, user) == null
                    ? Icon(Icons.person, size: 50, color: textSecondary)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  backgroundColor: const Color(0xFFF57C00),
                  radius: 16,
                  child: IconButton(
                    tooltip: 'Change profile photo',
                    icon: const Icon(Icons.camera_alt,
                        size: 14, color: Colors.white),
                    onPressed: _pickAndUploadImage,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            userModel?.name ?? 'Rental User',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            user?.email ?? '',
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: userModel?.isStaff == true
                  ? (isDark ? const Color(0xFF3B1D0E) : const Color(0xFFFFEDD5))
                  : (isDark
                      ? const Color(0xFF0F2A3F)
                      : const Color(0xFFE0F2FE)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              role,
              style: TextStyle(
                color: userModel?.isStaff == true
                    ? const Color(0xFFF57C00)
                    : const Color(0xFF0284C7),
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _nameController,
            enabled: _isEditing,
            decoration: const InputDecoration(
                labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined)),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: _isEditing ? 'Cancel profile editing' : 'Edit profile',
                icon: Icon(_isEditing ? Icons.close : Icons.edit,
                    color: const Color(0xFFF57C00)),
                onPressed: () => setState(() => _isEditing = !_isEditing),
              ),
              if (_isEditing)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isLoading ? null : _saveProfile,
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Profile'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
