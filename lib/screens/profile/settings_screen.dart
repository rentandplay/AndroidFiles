import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/mobile_controls.dart';
import '../../widgets/glass_app_bar.dart';
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rent & Play Support',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Location: Los Baños, Laguna\nEmail: support@rentandplay.ph\nOperating hours: 8:00 AM - 8:00 PM',
              style: TextStyle(color: textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'For return inquiries and verification assistance, you can visit our nearest pickup station or contact our customer support team.',
              style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authService = Provider.of<AuthService>(context);
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
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, topPadding + 16, 16, 32),
        children: [
          // 1. APPEARANCE
          _sectionHeader('APPEARANCE & THEME'),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
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
              onChanged: (val) => themeProvider.toggleTheme(val),
            ),
          ),

          const SizedBox(height: 22),

          // 2. NOTIFICATIONS
          _sectionHeader('NOTIFICATIONS'),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
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
                  onChanged: (val) =>
                      setState(() => _pushNotifications = val),
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
                  onChanged: (val) =>
                      setState(() => _rentalReminders = val),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 3. ACCOUNT & SECURITY
          _sectionHeader('ACCOUNT & SECURITY'),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
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
                              : const Color(0xFFDF762D).withValues(alpha: 0.12),
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
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 4. ABOUT & LEGAL
          _sectionHeader('ABOUT & SUPPORT'),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder),
            ),
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
                      onAccept: () {},
                      onDecline: () {},
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
