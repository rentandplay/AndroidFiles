import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../services/notification_service.dart';
import '../../services/business_settings.dart';
import '../../services/rental_offline_cache.dart';
import '../../utils/error_sanitizer.dart';
import '../../widgets/live_business_settings.dart';
import '../../widgets/mobile_controls.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../auth/forgot_password_screen.dart';
import '../auth/id_verification_screen.dart';
import '../auth/login_screen.dart';
import '../shared/terms_dialog.dart';

class SettingsScreen extends StatefulWidget {
  final UserModel? userModel;
  final Future<void> Function()? onSignOut;

  const SettingsScreen({
    super.key,
    this.userModel,
    this.onSignOut,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _preferencesBusy = true;
  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final result = await MobileApiService.instance.profile();
      final prefs =
          (result['user'] as Map?)?['notification_preferences'] as Map? ?? {};
      if (mounted) {
        setState(() {
          _pushNotifications = prefs['push_enabled'] != false;
          _rentalReminders = prefs['return_reminders'] != false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not load notification preferences.')));
      }
    } finally {
      if (mounted) setState(() => _preferencesBusy = false);
    }
  }

  Future<void> _savePreferences({bool? push, bool? reminders}) async {
    if (_preferencesBusy) return;
    setState(() => _preferencesBusy = true);
    try {
      await MobileApiService.instance.profile(method: 'PATCH', body: {
        'notification_preferences': {
          if (push != null) 'push_enabled': push,
          if (reminders != null) 'return_reminders': reminders,
        }
      });
      if (!mounted) return;
      setState(() {
        if (push != null) _pushNotifications = push;
        if (reminders != null) _rentalReminders = reminders;
      });
      if (push != null) {
        final notifications = context.read<RentalNotificationService>();
        await notifications.setPushPreference(push);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save notification preferences. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => _preferencesBusy = false);
    }
  }

  bool _pushNotifications = true;
  bool _rentalReminders = true;

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

  void _showHelpDialog(Color textPrimary, Color textSecondary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: Color(0xFFDF762D)),
            const SizedBox(width: 8),
            const Text('Help & Support'),
          ],
        ),
        content: LiveBusinessSettings(
            builder: (context, settings) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${settings.values['business_name'] ?? 'Rent & Play'} Support",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: textPrimary)),
                    const SizedBox(height: 6),
                    Text(
                      settings.loaded
                          ? 'Location: ${settings.values['location']}\nContact: ${settings.values['contact_phone']}\nOperating hours: ${formatBusinessTime(settings.values['opens_at'])} - ${formatBusinessTime(settings.values['closes_at'])}'
                          : (settings.error.isEmpty
                              ? 'Loading store details…'
                              : settings.error),
                      style: TextStyle(color: textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'For return inquiries and verification assistance, you can visit our nearest pickup station or contact our customer support team.',
                      style: TextStyle(
                          color: textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ],
                )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicyDialog(Color textPrimary, Color textSecondary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.privacy_tip_outlined, color: Color(0xFFDF762D)),
            SizedBox(width: 8),
            Expanded(child: Text('Privacy & Data Protection')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How Rent & Play Protects Your Information',
                style: TextStyle(fontWeight: FontWeight.w800, color: textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '• Account & Contact Details: Your name, email, and Philippine mobile number are used solely to verify bookings, coordinate resort delivery, and send rental updates.\n'
                '• ID Verification: Physical ID verification is checked by authorized staff at handoff to protect high-value sports and gaming equipment.\n'
                '• Payment Receipts: Uploaded GCash or InstaPay screenshots are restricted to authorized store administrators for payment verification.\n'
                '• Offline Cache Isolation: Offline rental passes and QR tickets cached on your device are scoped strictly to your account and cleared upon sign-out or cache reset.\n'
                '• Account Deletion: You may permanently delete your account and personal profile data anytime under Account & Security when you have no open rentals.',
                style: TextStyle(color: textSecondary, fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCachedData(String? uid) async {
    HapticFeedback.lightImpact();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await RentalOfflineCache.clearAll(scope: uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cached images and offline rental data cleared.'),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(AuthService authService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: const Text(
          'This will permanently remove your renter profile and personal data. Any active rentals must be returned or cancelled before deleting your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await authService.deleteAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorSanitizer.format(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authService = Provider.of<AuthService>(context);
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

    final isIdVerified =
        widget.userModel?.hasAcknowledgedIdRequirement ?? false;

    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: HeaderActionPod(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.pop(context),
        ),
        titleText: 'Settings',
      ),
      body: LiquidAmbientBackdrop(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, topPadding + 16, 16, 32),
          children: [
            // 1. APPEARANCE
            _sectionHeader('APPEARANCE & THEME'),
            GlassCard(
              borderRadius: 18,
              child: SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2C2218)
                        : const Color(0xFFFEF3EA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    themeProvider.isDarkMode
                        ? Icons.dark_mode_rounded
                        : Icons.wb_sunny_rounded,
                    color: mobileAccentText(context),
                    size: 20,
                  ),
                ),
                title: Text(
                  'Dark mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: textPrimary,
                  ),
                ),
                subtitle: Text(
                  themeProvider.isDarkMode
                      ? 'Dark appearance active'
                      : 'Light appearance active',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                value: themeProvider.isDarkMode,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  themeProvider.toggleTheme(val);
                },
              ),
            ),

            const SizedBox(height: 22),

            // 2. NOTIFICATIONS
            _sectionHeader('NOTIFICATIONS'),
            GlassCard(
              borderRadius: 18,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    secondary: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.notifications_active_outlined,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Push notifications',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Get instant updates about your equipment requests',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    value: _pushNotifications,
                    onChanged: _preferencesBusy
                        ? null
                        : (val) {
                            HapticFeedback.selectionClick();
                            _savePreferences(push: val);
                          },
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    secondary: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.alarm_on_rounded,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Return reminders',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Helpful alerts before your rental duration expires',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    value: _rentalReminders,
                    onChanged: _preferencesBusy
                        ? null
                        : (val) {
                            HapticFeedback.selectionClick();
                            _savePreferences(reminders: val);
                          },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 3. ACCOUNT & SECURITY
            _sectionHeader('ACCOUNT & SECURITY'),
            GlassCard(
              borderRadius: 18,
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.badge_outlined,
                        color: isIdVerified ? Colors.green : textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'ID Verification',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      isIdVerified
                          ? 'Government ID verified'
                          : 'Required to release high-value gear',
                      style: TextStyle(
                        fontSize: 12,
                        color: isIdVerified ? Colors.green : textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isIdVerified
                                ? Colors.green.withValues(alpha: 0.12)
                                : const Color(0xFFDF762D)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isIdVerified ? 'Verified' : 'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isIdVerified
                                  ? Colors.green
                                  : const Color(0xFFDF762D),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: textSecondary),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => IdVerificationScreen(
                            userModel: widget.userModel,
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Change password',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Send a reset code to your email',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing:
                        Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(
                            initialEmail: user?.email ?? '',
                          ),
                        ),
                      );
                    },
                  ),
                  if (user != null) ...[
                    Divider(height: 1, indent: 64, color: cardBorder),
                    ListTile(
                      key: const ValueKey('settings-delete-account-tile'),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.person_remove_outlined,
                          color: Theme.of(context).colorScheme.error,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        'Delete account & data',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      subtitle: Text(
                        'Permanently remove your profile and personal data',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: textSecondary),
                      onTap: () => _confirmDeleteAccount(authService),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 4. ABOUT & LEGAL
            _sectionHeader('ABOUT & SUPPORT'),
            GlassCard(
              borderRadius: 18,
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.description_outlined,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Terms & Conditions',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    trailing:
                        Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () {
                      TermsDialog.show(
                        context,
                        readOnly: true,
                      );
                    },
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                  ListTile(
                    key: const ValueKey('settings-privacy-policy-tile'),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.privacy_tip_outlined,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Privacy & Data Protection',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'How your ID, contact details, and records are protected',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing:
                        Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () =>
                        _showPrivacyPolicyDialog(textPrimary, textSecondary),
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.help_outline_rounded,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Help & Contact Support',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    trailing:
                        Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () => _showHelpDialog(textPrimary, textSecondary),
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                  ListTile(
                    key: const ValueKey('settings-clear-cache-tile'),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.cleaning_services_outlined,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Clear cached data',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Free up device memory used by images and offline passes',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    trailing:
                        Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () => _clearCachedData(user?.uid),
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E2838)
                            : const Color(0xFFEEF2F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: textPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'App version',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    trailing: Text(
                      'v1.0.0 (Release 2026)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (user != null) ...[
              const SizedBox(height: 28),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  backgroundColor: cardBg,
                  minimumSize: const Size.fromHeight(48),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: .35)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _confirmSignOut(authService),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Sign out of account',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFFDF762D),
            letterSpacing: 0.8,
          ),
        ),
      );
}
