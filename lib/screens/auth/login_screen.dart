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
import '../../widgets/google_logo_icon.dart';
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
  // The form uses a light surface in both app themes.
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
      if (e is MobileApiException) {
        errorMessage = e.userMessage;
      } else if (e is FirebaseAuthException) {
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
                'Sign-in is temporarily unavailable. Please try again later.';
            break;
          case 'network-request-failed':
            errorMessage =
                'Connection failed. Please check your internet connection and try again.';
            break;
          case 'too-many-requests':
            errorMessage =
                'Too many unsuccessful attempts. Please try again in a few minutes.';
            break;
          default:
            errorMessage = e.message ?? 'Could not sign in. Please try again.';
        }
      } else {
        final errText = e.toString().toLowerCase();
        if (errText.contains('socket') ||
            errText.contains('connection') ||
            errText.contains('network') ||
            errText.contains('host lookup')) {
          errorMessage =
              'Unable to connect to the server. Please check your network and try again.';
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: const Color(0xFFC53030),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: AppTheme.lightTextSecondary,
        fontSize: 14,
      ),
      errorMaxLines: 3,
      errorStyle: const TextStyle(color: _formError),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _formError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _formError, width: 1.5),
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 10, right: 8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(prefixIcon, color: AppTheme.brandOrange, size: 19),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 38),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.brandOrange, width: 1.6),
      ),
    );
  }

  Widget _featurePill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.brandOrange),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE2E8F0),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenSize = MediaQuery.sizeOf(context);
    final isCompactWidth = screenSize.width < 340;
    final logoHeight = isCompactWidth
        ? 122.0
        : (screenSize.height > 840 ? 186.0 : 148.0);

    return Scaffold(
      backgroundColor: AppTheme.brandNavy,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF060E1A),
              Color(0xFF0D1D35),
              Color(0xFF142A4A),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // Ambient glow behind the hero area
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 280,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.brandOrange.withValues(alpha: 0.28),
                            const Color(0xFF38BDF8).withValues(alpha: 0.08),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              LayoutBuilder(
                builder: (context, viewportConstraints) {
                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewportConstraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Navigation Bar (keeps logo clear of the top edge)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.white.withValues(alpha: 0.1),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      tooltip: 'Back to Catalog',
                                      onPressed: () {
                                        if (Navigator.of(context).canPop()) {
                                          Navigator.of(context).pop();
                                        } else {
                                          Navigator.of(context)
                                              .pushReplacement(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const CustomerHomeScreen(),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.14),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF22C55E),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Los Baños, Laguna',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Expanded Hero Showcase (centers the large logo with breathing room)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      height: logoHeight,
                                      width: screenSize.width * 0.84,
                                      child: Image.asset(
                                        'assets/images/logo_rent_and_play.png',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            Image.asset(
                                          'assets/images/logo.png',
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.sports_esports,
                                            size: 110,
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
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _featurePill(
                                          Icons.qr_code_scanner_rounded,
                                          'QR Verified',
                                        ),
                                        _featurePill(
                                          Icons.timer_outlined,
                                          'Live Timers',
                                        ),
                                        _featurePill(
                                          Icons.verified_user_outlined,
                                          'Fast Handoff',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Bottom White Sheet (Hugs form content cleanly & anchors flush at bottom)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(32),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 28,
                                    offset: const Offset(0, -6),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  24,
                                  20,
                                  24,
                                  bottomInset + 16,
                                ),
                                child: Form(
                                  key: _formKey,
                                  autovalidateMode: AutovalidateMode.disabled,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFFFF3E8),
                                                  Color(0xFFFFE4CC),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: const Color(0xFFFED7AA),
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.lock_person_rounded,
                                              color: _formAccent,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Welcome Back!',
                                                  style: TextStyle(
                                                    fontSize: 23,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppTheme.brandNavy,
                                                    height: 1.15,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'Manage your rentals and returns.',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: AppTheme
                                                        .lightTextSecondary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'EMAIL ADDRESS',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.lightTextSecondary,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextFormField(
                                        controller: _emailController,
                                        enabled: !_isLoading,
                                        autocorrect: false,
                                        textCapitalization:
                                            TextCapitalization.none,
                                        autofillHints: const [
                                          AutofillHints.email
                                        ],
                                        inputFormatters: [
                                          const LowercaseEmailFormatter(),
                                          LengthLimitingTextInputFormatter(254)
                                        ],
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        cursorColor: _formAccent,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                        decoration: _inputDecoration(
                                          hintText: 'Email address',
                                          prefixIcon: Icons.person_outline,
                                        ),
                                        validator: AccountValidation.email,
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'PASSWORD',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  AppTheme.lightTextSecondary,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              minimumSize: const Size(48, 28),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: _isLoading
                                                    ? null
                                                    : () => Navigator.of(
                                                            context)
                                                        .push(MaterialPageRoute(
                                                            builder: (_) =>
                                                                ForgotPasswordScreen(
                                                                    initialEmail:
                                                                        _emailController
                                                                            .text))),
                                            child: const Text(
                                              'Forgot password?',
                                              style: TextStyle(
                                                color: _formAccent,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      TextFormField(
                                        controller: _passwordController,
                                        enabled: !_isLoading,
                                        autofillHints: const [
                                          AutofillHints.password
                                        ],
                                        obscureText: _obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        cursorColor: _formAccent,
                                        onFieldSubmitted: (_) =>
                                            FocusScope.of(context).unfocus(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                        decoration: _inputDecoration(
                                          hintText: 'Password',
                                          prefixIcon: Icons.lock_outline,
                                          suffixIcon: IconButton(
                                            tooltip: _obscurePassword
                                                ? 'Show password'
                                                : 'Hide password',
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                              color:
                                                  AppTheme.lightTextSecondary,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              });
                                            },
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your password.';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 14),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(minHeight: 50),
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _formAccent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 13,
                                              horizontal: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            elevation: 2,
                                            shadowColor: _formAccent
                                                .withValues(alpha: 0.35),
                                          ),
                                          onPressed:
                                              _isLoading ? null : _handleLogin,
                                          child: _isLoading
                                              ? const Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      height: 20,
                                                      width: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text('Logging in…'),
                                                  ],
                                                )
                                              : const Text(
                                                  'Login',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Divider(
                                                color: Colors.grey.shade300),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 12),
                                            child: Text(
                                              'OR',
                                              style: TextStyle(
                                                color:
                                                    AppTheme.lightTextSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Divider(
                                                color: Colors.grey.shade300),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(minHeight: 48),
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFFFDFDFE),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 11,
                                              horizontal: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFCBD5E1),
                                            ),
                                          ),
                                          onPressed: _isLoading
                                              ? null
                                              : _handleGoogleSignIn,
                                          icon: const GoogleLogoIcon(size: 20),
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
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Wrap(
                                              alignment: WrapAlignment.center,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              spacing: 4,
                                              children: [
                                                const Text(
                                                  "Don't have an account? ",
                                                  style: TextStyle(
                                                    color: AppTheme
                                                        .lightTextSecondary,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const RegisterScreen(),
                                                      ),
                                                    );
                                                  },
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 4,
                                                    ),
                                                    minimumSize:
                                                        const Size(48, 30),
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    foregroundColor:
                                                        _formAccent,
                                                  ),
                                                  child: const Text(
                                                    'Register',
                                                    style: TextStyle(
                                                      color: _formAccent,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'Rent & Play • Customer & Operator Access',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color:
                                                    AppTheme.lightTextSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
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
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
