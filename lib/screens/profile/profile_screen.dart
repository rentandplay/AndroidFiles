import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_screen.dart';
import '../../widgets/notification_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
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

  Future<void> _loadUserData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userModel = await authService.getCurrentUserModel();
    if (userModel != null && mounted) {
      setState(() {
        _nameController.text = userModel.name;
        _phoneController.text = userModel.phone;
        _profileImageUrl = userModel.validIdUrl != null &&
                userModel.validIdUrl!.startsWith('http')
            ? userModel.validIdUrl
            : null;
      });
    }
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
      if (user == null) return;

      setState(() => _isLoading = true);

      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_pics')
          .child('${user.uid}.jpg');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'profileImageUrl': url,
      });

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
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      });

      if (!mounted) return;
      setState(() {
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
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textSecondary, size: 22),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
          ),
          RentalNotificationBell(color: textSecondary),
          const Padding(
            padding: EdgeInsets.only(right: 14.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFFED7AA),
              child: Text(
                'RP',
                style: TextStyle(
                  color: Color(0xFFC2410C),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<UserModel?>(
        future: authService.getCurrentUserModel(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userModel = snapshot.data;
          final role = userModel?.role.toUpperCase() ?? 'USER';
          final isAdmin = role == 'ADMIN' || role == 'OWNER';
          final isOwner = role == 'OWNER';
          final tabs = _settingsTabs(isAdmin);
          final selectedTab = tabs.any((tab) => tab['name'] == _selectedTab)
              ? _selectedTab
              : (isAdmin ? 'Business' : 'My profile');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
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

                const SizedBox(height: 20),

                // 2. Tab Content View
                if (isAdmin && selectedTab == 'Business')
                  _buildBusinessTabCard(isDark, cardBg, cardBorder, textPrimary,
                      textSecondary, inputFill, canEdit: isOwner)
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
                else
                  _buildUsersAccountTabCard(userModel, user, role, isDark,
                      cardBg, cardBorder, textPrimary, textSecondary, inputFill),

                const SizedBox(height: 30),

                // 3. Log Out Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      await authService.logout();
                      if (!context.mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.logout, size: 20),
                    label: const Text('Log Out',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
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

            return GestureDetector(
              onTap: () => setState(() => _selectedTab = name),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? const Color(0xFF332015)
                          : const Color(0xFFFEF3EA))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color:
                          isSelected ? const Color(0xFFF57C00) : textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFFF57C00)
                            : textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- BUSINESS TAB CARD ---
  Widget _buildBusinessTabCard(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color textPrimary,
    Color textSecondary,
    Color inputFill,
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
                        content: Text('Business settings saved successfully!')),
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
          const SizedBox(height: 16),
          SwitchListTile(
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: const Color(0xFFF57C00),
            ),
            title: Text('Dark Mode',
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
              color: ['ADMIN', 'OWNER'].contains(role)
                  ? (isDark ? const Color(0xFF3B1D0E) : const Color(0xFFFFEDD5))
                  : (isDark
                      ? const Color(0xFF0F2A3F)
                      : const Color(0xFFE0F2FE)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              role,
              style: TextStyle(
                color: ['ADMIN', 'OWNER'].contains(role)
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
