import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
    _startup = _loadInitialScreen();
  }

  Future<Widget> _loadInitialScreen() async {
    try {
      return await _resolveInitialScreen();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Rent & Play startup failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      // Gracefully fallback to CustomerHomeScreen instead of showing error screen
      return const CustomerHomeScreen();
    }
  }

  Future<Widget> _resolveInitialScreen() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    
    User? firebaseUser;
    try {
      firebaseUser = await auth.authStateChanges.first.timeout(const Duration(seconds: 4));
    } catch (_) {
      firebaseUser = auth.currentUser;
    }
    if (firebaseUser == null) return const CustomerHomeScreen();

    UserModel? user;
    try {
      user = await auth.getCurrentUserModel().timeout(const Duration(seconds: 5));
    } on MobileApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await auth.logout();
        return const LoginScreen();
      }
      // Gracefully fallback on other API/network errors
      return const CustomerHomeScreen();
    } catch (_) {
      // Gracefully fallback on connection timeout or network failure
      return const CustomerHomeScreen();
    }
    if (user == null) return const CustomerHomeScreen();

    if (_isAdmin(user)) {
      if (user.mustChangePassword) return const RequiredPasswordChangeScreen();
      try {
        await AdminFirestoreService.instance.restoreAdminSession().timeout(const Duration(seconds: 5));
      } catch (_) {}
      return AdminDashboardScreen(onSignedOut: _returnToLogin);
    }

    return const CustomerHomeScreen();
  }

  bool _isAdmin(UserModel user) => user.isStaff;

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
            return const CustomerHomeScreen();
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
