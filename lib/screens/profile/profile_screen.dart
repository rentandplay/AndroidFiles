import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_screen.dart';
import '../../widgets/notification_widgets.dart';
import '../../widgets/mobile_controls.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.showBackButton = true,
    this.showAppBar = true,
    this.onOpenEquipment,
    this.onSignOut,
  });

  final bool showBackButton;
  final bool showAppBar;
  final VoidCallback? onOpenEquipment;
  final Future<void> Function()? onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _businessNameController = TextEditingController(text: 'Rent & Play');
  final _locationController = TextEditingController(text: 'Los Baños, Laguna');
  final _currencyController = TextEditingController(text: 'PHP');
  final _timezoneController = TextEditingController(text: 'Asia/Manila');
  final _gracePeriodController = TextEditingController(text: '0');

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedTab = 'My profile';
  bool _isEditing = false;
  bool _isLoading = false;
  Uint8List? _imageBytes;
  String? _profileImageUrl;
  late Future<UserModel?> _profileFuture;
  String? _profileUserId;

  @override
  void initState() {
    super.initState();
    _profileUserId = context.read<AuthService>().currentUser?.uid;
    _profileFuture = _loadUserData();
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
    _profileFuture = _loadUserData();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _locationController.dispose();
    _currencyController.dispose();
    _timezoneController.dispose();
    _gracePeriodController.dispose();
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
      setState(() {
        _nameController.text = userModel?.name.trim().isNotEmpty == true
            ? userModel!.name.trim()
            : user?.displayName ?? '';
        _phoneController.text = userModel?.phone ?? '';
        _profileImageUrl = userModel?.profileImageUrl != null &&
                userModel!.profileImageUrl!.startsWith('http')
            ? userModel.profileImageUrl
            : null;
      });
    }
    return userModel;
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
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

      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_pics')
          .child('${user.uid}.jpg');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();

      await authService.updateProfileImageUrl(url);

      if (!mounted) return;
      setState(() {
        _profileImageUrl = url;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated successfully!')),
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
      );

      if (!mounted || updatedProfile.uid != _profileUserId) return;
      setState(() {
        _nameController.text = updatedProfile.name;
        _phoneController.text = updatedProfile.phone;
        _profileFuture = SynchronousFuture<UserModel?>(updatedProfile);
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
    final bgColor = isDark ? const Color(0xFF0B1320) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF131D2D) : Colors.white;
    final cardBorder =
        isDark ? const Color(0xFF1E2C42) : const Color(0xFFE2E8F0);
    final textPrimary =
        isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputFill =
        isDark ? const Color(0xFF1A2638) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: cardBg,
              elevation: 0.5,
              automaticallyImplyLeading: widget.showBackButton,
              leading: widget.showBackButton
                  ? IconButton(
                      icon: Icon(Icons.arrow_back, color: textPrimary),
                      onPressed: () => Navigator.pop(context),
                    )
                  : null,
              title: Text(
                'Profile & settings',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              actions: [
                if (user != null) RentalNotificationBell(color: textSecondary),
                const SizedBox(width: 8),
              ],
            )
          : null,
      bottomNavigationBar: user == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  key: const ValueKey('profile-sign-out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    backgroundColor: cardBg,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: .35)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed:
                      _isLoading ? null : () => _confirmSignOut(authService),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ),
      body: FutureBuilder<UserModel?>(
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
          final role = userModel?.role.toUpperCase() ?? 'CUSTOMER';
          final isAdmin = userModel?.isStaff ?? false;
          final isOwner = role == 'OWNER';
          final tabs = _settingsTabs(isAdmin);
          final selectedTab = tabs.any((tab) => tab['name'] == _selectedTab)
              ? _selectedTab
              : (isAdmin ? 'Business' : 'My profile');

          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Sub-Navigation Tabs
                _buildSubNavTabs(
                  isAdmin,
                  selectedTab,
                  isDark,
                  cardBg,
                  cardBorder,
                  textPrimary,
                  textSecondary,
                ),

                if (isAdmin && widget.onOpenEquipment != null) ...[
                  const SizedBox(height: 16),
                  _buildEquipmentMenu(
                    cardBg,
                    cardBorder,
                    textPrimary,
                    textSecondary,
                  ),
                ],

                const SizedBox(height: 14),

                // 2. Tab Content View
                if (isAdmin && selectedTab == 'Business')
                  _buildBusinessTabCard(isDark, cardBg, cardBorder, textPrimary,
                      textSecondary, inputFill,
                      canEdit: isOwner)
                else if (selectedTab == 'Appearance')
                  _buildAppearanceTabCard(themeProvider, isDark, cardBg,
                      cardBorder, textPrimary, textSecondary)
                else if (isAdmin &&
                    (selectedTab == 'Users' ||
                        selectedTab == 'Account & security'))
                  _buildUsersAccountTabCard(userModel, user, role, isDark,
                      cardBg, cardBorder, textPrimary, textSecondary, inputFill)
                else if (isAdmin && selectedTab == 'Preferences')
                  _buildPreferencesTabCard(
                      isDark, cardBg, cardBorder, textPrimary, textSecondary)
                else if (!isAdmin && user == null)
                  _buildGuestProfileCard(
                      cardBg, cardBorder, textPrimary, textSecondary)
                else if (!isAdmin)
                  _buildCustomerProfileCard(userModel, user, isDark, cardBg,
                      cardBorder, textPrimary, textSecondary)
                else
                  _buildUsersAccountTabCard(
                      userModel,
                      user,
                      role,
                      isDark,
                      cardBg,
                      cardBorder,
                      textPrimary,
                      textSecondary,
                      inputFill),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Map<String, Object>> _settingsTabs(bool isAdmin) {
    if (!isAdmin) {
      return [
        {'name': 'My profile', 'icon': Icons.person_outline},
        {'name': 'Appearance', 'icon': Icons.wb_sunny_outlined},
      ];
    }

    return [
      {'name': 'Business', 'icon': Icons.storefront_outlined},
      {'name': 'Appearance', 'icon': Icons.wb_sunny_outlined},
      {'name': 'Preferences', 'icon': Icons.tune},
      {'name': 'Account & security', 'icon': Icons.lock_outline},
    ];
  }

  Widget _buildEquipmentMenu(
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) =>
      Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2E7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFFC45E1B),
            ),
          ),
          title: Text(
            'Equipment',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            'View equipment and print labels',
            style: TextStyle(color: textSecondary),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
          onTap: widget.onOpenEquipment,
        ),
      );

  // --- SUB NAV TABS ---
  Widget _buildSubNavTabs(
    bool isAdmin,
    String selectedTab,
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
  ) {
    final tabs = _settingsTabs(isAdmin);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          children: tabs.map((tab) {
            final name = tab['name'] as String;
            final icon = tab['icon'] as IconData;
            final isSelected = selectedTab == name;

            return TextButton.icon(
              onPressed: () => setState(() => _selectedTab = name),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                foregroundColor:
                    isSelected ? mobileAccentText(context) : textSecondary,
                backgroundColor: isSelected
                    ? (isDark
                        ? const Color(0xFF332015)
                        : const Color(0xFFFEF3EA))
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(icon, size: 16),
              label: Text(name,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500)),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- BUSINESS TAB CARD ---
  Widget _buildBusinessTabCard(bool isDark, Color cardBg, Color cardBorder,
      Color textPrimary, Color textSecondary, Color inputFill,
      {required bool canEdit}) {
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
            'BUSINESS PROFILE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF57C00),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your rental workspace',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            canEdit
                ? 'Business details are shared with everyone in this workspace.'
                : 'Only the super admin owner can change shared business settings.',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 20),

          // Business Name & Location
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Business name',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _businessNameController,
                      enabled: canEdit,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        fillColor: inputFill,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFF57C00))),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Location',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _locationController,
                      enabled: canEdit,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        fillColor: inputFill,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFF57C00))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Currency & Timezone
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Currency',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _currencyController,
                      readOnly: true,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        fillColor: inputFill,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFF57C00))),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Reports display Philippine pesos (PHP)',
                        style: TextStyle(fontSize: 9, color: textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Timezone',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _timezoneController,
                      readOnly: true,
                      style: TextStyle(fontSize: 13, color: textPrimary),
                      decoration: InputDecoration(
                        fillColor: inputFill,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cardBorder)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFF57C00))),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('Reports use Philippine time (Asia/Manila)',
                        style: TextStyle(fontSize: 9, color: textSecondary)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Grace period
          Text('Default late grace period (hours)',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: textPrimary)),
          const SizedBox(height: 6),
          TextField(
            controller: _gracePeriodController,
            enabled: canEdit,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 13, color: textPrimary),
            decoration: InputDecoration(
              fillColor: inputFill,
              filled: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cardBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFF57C00))),
            ),
          ),
          const SizedBox(height: 4),
          Text('Administrative default for overdue calculations',
              style: TextStyle(fontSize: 10, color: textSecondary)),

          const SizedBox(height: 20),

          // Notice
          if (canEdit)
            const Text('Changes apply after you select Save business settings.',
                style: TextStyle(fontSize: 11, color: Color(0xFFF57C00))),

          if (canEdit) const SizedBox(height: 16),

          if (canEdit)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {},
                  child: Text('Discard changes',
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Business settings saved successfully!')),
                    );
                  },
                  child: const Text('Save business settings',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
        ],
      ),
    );
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
          SwitchListTile(
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
          ),
        ],
      ),
    );
  }

  // --- PREFERENCES TAB CARD ---
  Widget _buildPreferencesTabCard(
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
          const Text('PREFERENCES',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF57C00),
                  letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text('Workspace Preferences',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textPrimary)),
          const SizedBox(height: 12),
          Text('• ESP32 terminal on standby',
              style: TextStyle(fontSize: 13, color: textSecondary)),
          const SizedBox(height: 6),
          Text('• Real-Time Notification Sound Enabled',
              style: TextStyle(fontSize: 13, color: textSecondary)),
        ],
      ),
    );
  }

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
  ) {
    final name = _profileValue(userModel?.name.trim().isNotEmpty == true
        ? userModel!.name
        : user?.displayName?.toString());
    final email = _profileValue(userModel?.email.trim().isNotEmpty == true
        ? userModel!.email
        : user?.email?.toString());
    final avatarImage = _imageBytes != null
        ? MemoryImage(_imageBytes!) as ImageProvider
        : _profileImageUrl != null
            ? NetworkImage(_profileImageUrl!) as ImageProvider
            : null;

    return Container(
      key: const ValueKey('customer-profile-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: mobileAccentText(context),
                                shape: BoxShape.circle,
                                border: Border.all(color: cardBg, width: 2),
                              ),
                              child: _isLoading
                                  ? Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: isDark
                                              ? const Color(0xFF0F172A)
                                              : Colors.white),
                                    )
                                  : Icon(Icons.camera_alt_outlined,
                                      size: 14,
                                      color: isDark
                                          ? const Color(0xFF0F172A)
                                          : Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color:
                                name == 'Not set' ? textSecondary : textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(email,
                        style: TextStyle(
                            color: textSecondary, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
              if (!_isEditing) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('profile-edit'),
                  tooltip: 'Edit profile',
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _isEditing = true),
                  color: mobileAccentText(context),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: cardBorder),
          ),
          if (_isEditing) ...[
            TextField(
              controller: _nameController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 150,
              decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline)),
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
                  prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: textPrimary),
                    onPressed: _isLoading
                        ? null
                        : () => setState(() {
                              _nameController.text =
                                  userModel?.name.trim().isNotEmpty == true
                                      ? userModel!.name
                                      : user?.displayName?.toString() ?? '';
                              _phoneController.text = userModel?.phone ?? '';
                              _isEditing = false;
                            }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
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
                                    : Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ] else ...[
            _customerDetailRow(Icons.phone_outlined, 'Phone number',
                _profileValue(userModel?.phone), textPrimary, textSecondary),
            const SizedBox(height: 14),
            _customerDetailRow(
              Icons.calendar_month_outlined,
              'Member since',
              userModel?.createdAt == null
                  ? 'Not set'
                  : DateFormat('MMMM yyyy', 'en').format(userModel!.createdAt!),
              textPrimary,
              textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  String _profileValue(String? value) =>
      value?.trim().isNotEmpty == true ? value!.trim() : 'Not set';

  Widget _customerDetailRow(IconData icon, String label, String value,
          Color textPrimary, Color textSecondary) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(color: textSecondary, fontSize: 12)),
                const SizedBox(height: 3),
                Text(value,
                    style: TextStyle(
                        color: value == 'Not set' ? textSecondary : textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );

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
                backgroundImage: _imageBytes != null
                    ? MemoryImage(_imageBytes!)
                    : (_profileImageUrl != null
                        ? NetworkImage(_profileImageUrl!) as ImageProvider
                        : null),
                child: (_imageBytes == null && _profileImageUrl == null)
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

          // Inputs
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  enabled: _isEditing,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(color: textSecondary),
                    fillColor: inputFill,
                    filled: true,
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: cardBorder)),
                    focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFF57C00))),
                    prefixIcon: Icon(Icons.person_outline,
                        size: 18, color: textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  enabled: _isEditing,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(fontSize: 13, color: textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: TextStyle(color: textSecondary),
                    fillColor: inputFill,
                    filled: true,
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: cardBorder)),
                    focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFF57C00))),
                    prefixIcon: Icon(Icons.phone_outlined,
                        size: 18, color: textSecondary),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
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
