import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/account_validation.dart';
import '../../services/admin_firestore_service.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'required_password_change_screen.dart';
import 'id_verification_screen.dart';
import '../user/customer_home_screen.dart';
import '../admin/admin_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // The form uses a white surface in both app themes.
  static const _formAccent = Color(0xFF9A471B);
  static const _formError = Color(0xFFB42318);
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openAdminWorkspace() {
    final navigator = Navigator.of(context);
    void returnToLogin() {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminDashboardScreen(onSignedOut: returnToLogin),
      ),
      (route) => false,
    );
  }

  void _handleLogin() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.loginWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      UserModel? userModel = await authService.getCurrentUserModel();

      if (!mounted) return;

      if (userModel != null) {
        if (userModel.isStaff) {
          if (userModel.mustChangePassword) {
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const RequiredPasswordChangeScreen()),
                (_) => false);
            return;
          }
          await AdminFirestoreService.instance.restoreAdminSession();
          if (!mounted) return;
          _openAdminWorkspace();
          return;
        }

        if (!userModel.hasAcknowledgedIdRequirement ||
            !userModel.hasAcceptedTerms) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => IdVerificationScreen(userModel: userModel),
            ),
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
            (route) => false,
          );
        }
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'Could not log in. Please try again.';
      if (e is MobileApiException) errorMessage = e.userMessage;
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            errorMessage = 'User account not found. Please register first.';
            break;
          case 'wrong-password':
          case 'invalid-credential':
            errorMessage = 'Incorrect email or password. Please try again.';
            break;
          case 'invalid-email':
            errorMessage =
                'Invalid email address format. Please enter a valid email.';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled.';
            break;
          case 'operation-not-allowed':
            errorMessage =
                'Email/Password sign-in is disabled in Firebase Console. Please enable Email/Password provider in Authentication settings.';
            break;
          default:
            errorMessage = e.message ?? e.toString();
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      UserModel? userModel = await authService.signInWithGoogle();

      if (!mounted) return;

      if (userModel != null) {
        if (userModel.isStaff) {
          if (userModel.mustChangePassword) {
            Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const RequiredPasswordChangeScreen()),
                (_) => false);
            return;
          }
          await AdminFirestoreService.instance.restoreAdminSession();
          if (!mounted) return;
          _openAdminWorkspace();
          return;
        }

        if (!userModel.hasAcknowledgedIdRequirement ||
            !userModel.hasAcceptedTerms) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => IdVerificationScreen(userModel: userModel),
            ),
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Sign-In Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.brandNavy,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                children: [
                  // Top Section (Logo & Tagline on Dark Navy)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 12.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 4),
                        // Unclipped Prominent Logo Asset
                        SizedBox(
                          height: 80,
                          child: Image.asset(
                            'assets/images/logo_rent_and_play.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.sports_esports,
                                size: 70,
                                color: AppTheme.brandOrange,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Play More. Rent Smarter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),

                  // Bottom White Rounded Container (Login Form)
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 24.0),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.disabled,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Welcome Back!',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.brandNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Manage your rentals and returns.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.lightTextSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'EMAIL ADDRESS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.lightTextSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _emailController,
                              enabled: !_isLoading,
                              autocorrect: false,
                              textCapitalization: TextCapitalization.none,
                              autofillHints: const [AutofillHints.email],
                              inputFormatters: [
                                const LowercaseEmailFormatter(),
                                LengthLimitingTextInputFormatter(254)
                              ],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              cursorColor: _formAccent,
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.black87),
                              decoration: InputDecoration(
                                hintText: 'Email address',
                                hintStyle: const TextStyle(
                                    color: AppTheme.lightTextSecondary,
                                    fontSize: 14),
                                errorMaxLines: 3,
                                errorStyle: const TextStyle(color: _formError),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: _formError),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: _formError, width: 1.5),
                                ),
                                prefixIcon: const Icon(Icons.person_outline,
                                    color: AppTheme.brandOrange, size: 20),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 16),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: AppTheme.brandOrange, width: 1.5),
                                ),
                              ),
                              validator: AccountValidation.email,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'PASSWORD',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.lightTextSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _passwordController,
                              enabled: !_isLoading,
                              autofillHints: const [AutofillHints.password],
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              cursorColor: _formAccent,
                              onFieldSubmitted: (_) =>
                                  FocusScope.of(context).unfocus(),
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.black87),
                              decoration: InputDecoration(
                                hintText: 'Password',
                                hintStyle: const TextStyle(
                                    color: AppTheme.lightTextSecondary,
                                    fontSize: 14),
                                errorMaxLines: 3,
                                errorStyle: const TextStyle(color: _formError),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: _formError),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: _formError, width: 1.5),
                                ),
                                prefixIcon: const Icon(Icons.lock_outline,
                                    color: AppTheme.brandOrange, size: 20),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppTheme.lightTextSecondary,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 16),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: AppTheme.brandOrange, width: 1.5),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: _isLoading
                                    ? null
                                    : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                ForgotPasswordScreen(
                                                    initialEmail:
                                                        _emailController
                                                            .text))),
                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: _formAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 50),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _formAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: _isLoading ? null : _handleLogin,
                                child: _isLoading
                                    ? const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                            SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white)),
                                            SizedBox(width: 10),
                                            Text('Logging in…')
                                          ])
                                    : const Text(
                                        'Login',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                    child:
                                        Divider(color: Colors.grey.shade300)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'OR',
                                    style: TextStyle(
                                        color: AppTheme.lightTextSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Expanded(
                                    child:
                                        Divider(color: Colors.grey.shade300)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 50),
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                onPressed:
                                    _isLoading ? null : _handleGoogleSignIn,
                                icon: const Icon(Icons.g_mobiledata,
                                    size: 28, color: Colors.red),
                                label: const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              children: [
                                const Text(
                                  "Don't have an account? ",
                                  style: TextStyle(
                                      color: AppTheme.lightTextSecondary,
                                      fontSize: 13),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      foregroundColor: _formAccent),
                                  child: const Text(
                                    'Register',
                                    style: TextStyle(
                                      color: _formAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                'Rent & Play • Customer & Operator Access',
                                style: TextStyle(
                                  color: AppTheme.lightTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Back to Catalog',
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const CustomerHomeScreen()),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
