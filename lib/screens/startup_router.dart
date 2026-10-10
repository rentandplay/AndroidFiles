import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/mobile_api_service.dart';
import '../services/admin_firestore_service.dart';
import 'auth/required_password_change_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'auth/login_screen.dart';
import 'user/customer_home_screen.dart';

/// Restores the correct interface after Firebase restores a saved login.
///
/// This only resolves the app's initial screen. Login and logout flows already
/// navigate explicitly, so listening to later auth changes here could create a
/// second dashboard underneath the screen they navigate to.
class StartupRouter extends StatefulWidget {
  const StartupRouter({super.key});

  @override
  State<StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<StartupRouter> {
  late Future<Widget> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _resolveInitialScreen();
  }

  Future<Widget> _resolveInitialScreen() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final firebaseUser = await auth.authStateChanges.first;
    if (firebaseUser == null) return const CustomerHomeScreen();

    UserModel? user;
    try {
      user = await auth.getCurrentUserModel();
    } on MobileApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await auth.logout();
        return const LoginScreen();
      }
      rethrow;
    }
    if (user == null) return const CustomerHomeScreen();

    if (_isAdmin(user)) {
      if (user.mustChangePassword) return const RequiredPasswordChangeScreen();
      await AdminFirestoreService.instance.restoreAdminSession();
      return AdminDashboardScreen(onSignedOut: _returnToLogin);
    }

    return const CustomerHomeScreen();
  }

  bool _isAdmin(UserModel user) => user.isStaff;

  void _retry() {
    setState(() {
      _startup = _resolveInitialScreen();
    });
  }

  void _returnToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupLoadingScreen();
          }
          if (snapshot.hasError) {
            return _StartupErrorScreen(onRetry: _retry);
          }
          return snapshot.data ?? const CustomerHomeScreen();
        },
      );
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  height: 100,
                  child: Image(
                      image:
                          AssetImage('assets/images/logo_rent_and_play.png'))),
              SizedBox(height: 24),
              SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(height: 16),
              Text('Opening Rent & Play…'),
            ],
          ),
        ),
      );
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Could not open Rent & Play',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
}
