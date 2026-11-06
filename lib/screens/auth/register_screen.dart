import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/account_validation.dart';
import '../../widgets/google_logo_icon.dart';
import '../shared/terms_dialog.dart';
import '../user/customer_home_screen.dart';
import 'id_verification_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _formAccent = Color(0xFF9A471B);
  static const _formError = Color(0xFFB42318);

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Timer? _resendTimer;
  String? _requestedEmail;
  String _verificationToken = '';
  int _resendSeconds = 0;
  bool _codeSent = false;
  bool _emailVerified = false;
  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  String? _dynamicTermsText;
  String _currentTermsVersion = rentalTermsVersion;

  String get _currentEmail => _emailController.text.trim().toLowerCase();
  bool get _codeMatchesCurrentEmail =>
      _codeSent && _requestedEmail != null && _requestedEmail == _currentEmail;
  bool get _verifiedCurrentEmail =>
      _emailVerified &&
      _verificationToken.isNotEmpty &&
      _requestedEmail == _currentEmail;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleEmailChange);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleEmailChange() {
    if (_verificationToken.isEmpty || _requestedEmail == _currentEmail) return;
    setState(() {
      _verificationToken = '';
      _emailVerified = false;
    });
  }

  String? _validateName(String? value, String label) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Please enter your $label.';
    if (name.length < 2) return '$label must be at least 2 letters.';
    if (name.length > 60) return '$label must be 60 characters or fewer.';
    if (!RegExp(r"^[\p{L}\p{M}\s\-']+$", unicode: true).hasMatch(name)) {
      return 'Use letters, spaces, or hyphens only.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim().toLowerCase();
    if (email.isEmpty) return 'Please enter your email address.';
    if (email.contains(' ')) return 'Email cannot contain spaces.';
    if (!RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
    ).hasMatch(email)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'Please enter your phone number.';
    final clean = phone.replaceAll(RegExp(r'[\s().-]'), '');
    if (!RegExp(r'^(?:\+?63|0)?9\d{9}$').hasMatch(clean)) {
      return 'Enter a valid Philippine number (e.g. 0912 345 6789).';
    }
    return null;
  }

  String _normalizedPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final mobile = digits.startsWith('63')
        ? digits.substring(2)
        : digits.startsWith('0')
            ? digits.substring(1)
            : digits;
    return '+63$mobile';
  }

  String? _validatePassword(String? value) {
    final pass = value ?? '';
    if (pass.isEmpty) return 'Please enter a password.';
    if (pass.length < 6) return 'Password must be at least 6 characters.';
    if (pass.length > 64) return 'Password must be 64 characters or fewer.';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password.';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  String? _validateCode(String? value) {
    if (!_codeMatchesCurrentEmail) return 'Send a code to this email first.';
    final code = (value ?? '').trim();
    if (code.isEmpty) return 'Enter the 6-digit code.';
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return 'Code must be exactly 6 digits.';
    }
    return null;
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendVerificationCode() async {
    final emailError = _validateEmail(_currentEmail);
    if (emailError != null) {
      _showMessage(emailError, isError: true);
      return;
    }
    final email = _currentEmail;
    setState(() => _isSendingCode = true);
    try {
      await MobileApiService.instance.sendRegistrationEmailCode(email);
      if (!mounted) return;
      setState(() {
        _requestedEmail = email;
        _codeSent = true;
        _emailVerified = false;
        _verificationToken = '';
        _codeController.clear();
      });
      _startResendCountdown();
      _showMessage('Verification code sent to $email.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _verifyEmailCode() async {
    if (!_codeMatchesCurrentEmail) {
      _showMessage('Send a code to this email first.', isError: true);
      return;
    }
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showMessage('Enter the 6-digit code sent to your email.', isError: true);
      return;
    }
    final email = _currentEmail;
    setState(() => _isVerifyingCode = true);
    try {
      final proof = await MobileApiService.instance.verifyRegistrationEmailCode(
        email: email,
        code: code,
      );
      if (!mounted) return;
      if (_currentEmail != email || _requestedEmail != email) {
        _showMessage(
          'Email changed. Please verify your new email address.',
          isError: true,
        );
        return;
      }
      _resendTimer?.cancel();
      setState(() {
        _verificationToken = proof;
        _emailVerified = true;
        _resendSeconds = 0;
      });
      _showMessage('Email verified successfully!');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  Future<void> _handleRegister() async {
    if (!_acceptedTerms) {
      _showMessage(
        'Please read and accept the Terms & Conditions.',
        isError: true,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_verifiedCurrentEmail) {
      _showMessage(
        'Please verify your email address before creating your account.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final name =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
      final UserModel? newUser = await authService.registerWithEmailAndPassword(
        name: name,
        email: _currentEmail,
        password: _passwordController.text,
        phone: _normalizedPhone(_phoneController.text),
        verificationToken: _verificationToken,
        termsVersion: _currentTermsVersion,
      );

      if (!mounted) return;
      if (newUser != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => IdVerificationScreen(userModel: newUser),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      if (error is MobileApiException &&
          error.statusCode == 403 &&
          error.message.toLowerCase().contains('verification expired')) {
        _resendTimer?.cancel();
        _codeController.clear();
        setState(() {
          _requestedEmail = null;
          _codeSent = false;
          _emailVerified = false;
          _verificationToken = '';
          _resendSeconds = 0;
        });
      }
      _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignUp() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userModel = await authService.signInWithGoogle();
      if (!mounted || userModel == null) return;
      if (!userModel.hasAcknowledgedIdRequirement ||
          !userModel.hasAcceptedTerms ||
          userModel.phone.trim().isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => IdVerificationScreen(userModel: userModel),
          ),
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const CustomerHomeScreen()),
          (route) => false,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Google Sign-In failed: ${_errorMessage(error)}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showTerms() async {
    if (_dynamicTermsText == null) {
      try {
        final result = await MobileApiService.instance.terms();
        if (result['terms_and_conditions'] is String &&
            (result['terms_and_conditions'] as String).trim().isNotEmpty) {
          _dynamicTermsText = result['terms_and_conditions'] as String;
        }
        if (result['terms_version'] is String &&
            (result['terms_version'] as String).trim().isNotEmpty) {
          _currentTermsVersion = result['terms_version'] as String;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    await TermsDialog.show(
      context,
      termsText: _dynamicTermsText,
      onAccept: () {
        if (mounted) setState(() => _acceptedTerms = true);
      },
      onDecline: () {
        if (mounted) setState(() => _acceptedTerms = false);
      },
    );
  }

  String _errorMessage(Object error) {
    if (error is MobileApiException) return error.userMessage;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'This email is already registered. Please log in instead.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'operation-not-allowed':
          return 'Sign-up is temporarily disabled. Please contact support.';
        case 'network-request-failed':
          return 'Connection failed. Please check your internet and try again.';
        default:
          return error.message ?? 'Could not create account. Please try again.';
      }
    }
    return 'Could not complete registration. Please try again.';
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor:
              isError ? const Color(0xFFC53030) : const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.lightTextSecondary,
            letterSpacing: 0.8,
          ),
        ),
      );

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
    final isCompact = screenSize.width < 350;

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
              // Ambient glow behind the hero header
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 280,
                      height: 220,
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

              SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Navigation Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.1),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Back to Login',
                              onPressed: () {
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                } else {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
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
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
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

                    // Hero Showcase Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 104,
                            width: screenSize.width * 0.72,
                            child: Image.asset(
                              'assets/images/logo_rent_and_play.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.sports_esports,
                                  size: 80,
                                  color: AppTheme.brandOrange,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Play More. Rent Smarter.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 19,
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

                    // Bottom White Sheet Form
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
                          22,
                          24,
                          bottomInset + 20,
                        ),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.disabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Form Welcome Header
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
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
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFFED7AA),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.person_add_alt_1_rounded,
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
                                          'Create Account',
                                          style: TextStyle(
                                            fontSize: 23,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.brandNavy,
                                            height: 1.15,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Add your details to start renting gear.',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.lightTextSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Name Fields
                              if (isCompact) ...[
                                _fieldLabel('FIRST NAME'),
                                TextFormField(
                                  controller: _firstNameController,
                                  enabled: !_isLoading,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  cursorColor: _formAccent,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                  decoration: _inputDecoration(
                                    hintText: 'First name',
                                    prefixIcon: Icons.person_outline,
                                  ),
                                  validator: (v) =>
                                      _validateName(v, 'First name'),
                                ),
                                const SizedBox(height: 12),
                                _fieldLabel('LAST NAME'),
                                TextFormField(
                                  controller: _lastNameController,
                                  enabled: !_isLoading,
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.next,
                                  cursorColor: _formAccent,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                  decoration: _inputDecoration(
                                    hintText: 'Last name',
                                    prefixIcon: Icons.person_outline,
                                  ),
                                  validator: (v) =>
                                      _validateName(v, 'Last name'),
                                ),
                              ] else ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _fieldLabel('FIRST NAME'),
                                          TextFormField(
                                            controller: _firstNameController,
                                            enabled: !_isLoading,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            textInputAction:
                                                TextInputAction.next,
                                            cursorColor: _formAccent,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                            decoration: _inputDecoration(
                                              hintText: 'First name',
                                              prefixIcon: Icons.person_outline,
                                            ),
                                            validator: (v) =>
                                                _validateName(v, 'First name'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _fieldLabel('LAST NAME'),
                                          TextFormField(
                                            controller: _lastNameController,
                                            enabled: !_isLoading,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            textInputAction:
                                                TextInputAction.next,
                                            cursorColor: _formAccent,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                            decoration: _inputDecoration(
                                              hintText: 'Last name',
                                              prefixIcon: Icons.person_outline,
                                            ),
                                            validator: (v) =>
                                                _validateName(v, 'Last name'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),

                              // Email Address Field
                              _fieldLabel('EMAIL ADDRESS'),
                              TextFormField(
                                controller: _emailController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                cursorColor: _formAccent,
                                inputFormatters: [
                                  const LowercaseEmailFormatter(),
                                  LengthLimitingTextInputFormatter(254),
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                                decoration: _inputDecoration(
                                  hintText: 'name@example.com',
                                  prefixIcon: Icons.mail_outline,
                                ),
                                validator: _validateEmail,
                              ),

                              // Email Verification Status & Action
                              if (_verifiedCurrentEmail) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE7F5EC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFA3D9B8),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF16824B),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Email verified: $_requestedEmail',
                                          style: const TextStyle(
                                            color: Color(0xFF16824B),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _isSendingCode ||
                                            _isVerifyingCode ||
                                            (_codeMatchesCurrentEmail &&
                                                _resendSeconds > 0)
                                        ? null
                                        : _sendVerificationCode,
                                    icon: _isSendingCode
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _formAccent,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.mark_email_unread_outlined,
                                            size: 16,
                                          ),
                                    label: Text(
                                      _codeMatchesCurrentEmail &&
                                              _resendSeconds > 0
                                          ? 'Resend in ${_resendSeconds}s'
                                          : (_codeMatchesCurrentEmail
                                              ? 'Resend code'
                                              : 'Send verification code'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _formAccent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              ],

                              // 6-digit Code Input Card
                              if (_codeMatchesCurrentEmail &&
                                  !_verifiedCurrentEmail) ...[
                                Container(
                                  margin: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 6,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.mark_email_read_outlined,
                                            size: 16,
                                            color: _formAccent,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Enter code sent to $_requestedEmail',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.brandNavy,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _codeController,
                                              enabled: !_isLoading,
                                              keyboardType:
                                                  TextInputType.number,
                                              textInputAction:
                                                  TextInputAction.done,
                                              autofillHints: const [
                                                AutofillHints.oneTimeCode
                                              ],
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                                LengthLimitingTextInputFormatter(
                                                    6),
                                              ],
                                              cursorColor: _formAccent,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 2.0,
                                              ),
                                              decoration: _inputDecoration(
                                                hintText: '6-digit code',
                                                prefixIcon:
                                                    Icons.verified_user_outlined,
                                              ),
                                              validator: _validateCode,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          SizedBox(
                                            height: 52,
                                            child: ElevatedButton(
                                              onPressed: _isVerifyingCode
                                                  ? null
                                                  : _verifyEmailCode,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _formAccent,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 18,
                                                ),
                                                elevation: 1,
                                              ),
                                              child: _isVerifyingCode
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Text(
                                                      'Verify',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Code expires in 10 minutes. Check your inbox or spam.',
                                        style: TextStyle(
                                          color: AppTheme.lightTextSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),

                              // Phone Number Field
                              _fieldLabel('PHONE NUMBER'),
                              TextFormField(
                                controller: _phoneController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                cursorColor: _formAccent,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[+0-9() .-]'),
                                  ),
                                  LengthLimitingTextInputFormatter(20),
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                                decoration: _inputDecoration(
                                  hintText: '0912 345 6789',
                                  prefixIcon: Icons.phone_outlined,
                                ),
                                validator: _validatePhone,
                              ),
                              const SizedBox(height: 14),

                              // Password Field (Clean & Secured: 6+ characters)
                              _fieldLabel('PASSWORD'),
                              TextFormField(
                                controller: _passwordController,
                                enabled: !_isLoading,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.next,
                                cursorColor: _formAccent,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(64),
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                                decoration: _inputDecoration(
                                  hintText: 'At least 6 characters',
                                  prefixIcon: Icons.lock_outline,
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
                                ),
                                validator: _validatePassword,
                              ),
                              const SizedBox(height: 14),

                              // Confirm Password Field
                              _fieldLabel('CONFIRM PASSWORD'),
                              TextFormField(
                                controller: _confirmPasswordController,
                                enabled: !_isLoading,
                                obscureText: _obscureConfirmPassword,
                                textInputAction: TextInputAction.done,
                                cursorColor: _formAccent,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(64),
                                ],
                                onFieldSubmitted: (_) =>
                                    FocusScope.of(context).unfocus(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                                decoration: _inputDecoration(
                                  hintText: 'Re-enter your password',
                                  prefixIcon: Icons.lock_reset_rounded,
                                  suffixIcon: IconButton(
                                    tooltip: _obscureConfirmPassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: AppTheme.lightTextSecondary,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: _validateConfirmPassword,
                              ),
                              const SizedBox(height: 16),

                              // Terms & Conditions Checkbox Card
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _acceptedTerms
                                        ? const Color(0xFFFED7AA)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: _acceptedTerms,
                                        activeColor: _formAccent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        onChanged: _isLoading
                                            ? null
                                            : (value) => setState(
                                                  () => _acceptedTerms =
                                                      value ?? false,
                                                ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            const Text(
                                              'I agree to the ',
                                              style: TextStyle(
                                                color: Color(0xFF475569),
                                                fontSize: 12.5,
                                                height: 1.4,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: _isLoading
                                                  ? null
                                                  : _showTerms,
                                              child: const Text(
                                                'Terms & Conditions',
                                                style: TextStyle(
                                                  color: _formAccent,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                            const Text(
                                              ' for equipment rentals.',
                                              style: TextStyle(
                                                color: Color(0xFF475569),
                                                fontSize: 12.5,
                                                height: 1.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Create Account Button
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
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 2,
                                    shadowColor:
                                        _formAccent.withValues(alpha: 0.35),
                                  ),
                                  onPressed:
                                      _isLoading ? null : _handleRegister,
                                  child: _isLoading
                                      ? const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text('Creating account…'),
                                          ],
                                        )
                                      : const Text(
                                          'Create Account',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // OR Divider
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(color: Colors.grey.shade300),
                                  ),
                                  const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: AppTheme.lightTextSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: Colors.grey.shade300),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Continue with Google Button
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 48),
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFDFDFE),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    side: const BorderSide(
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  onPressed:
                                      _isLoading ? null : _handleGoogleSignUp,
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
                              const SizedBox(height: 14),

                              // Bottom Navigation to Login
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
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
                                          'Already have an account? ',
                                          style: TextStyle(
                                            color: AppTheme.lightTextSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pushReplacement(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const LoginScreen(),
                                              ),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            minimumSize: const Size(48, 30),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            foregroundColor: _formAccent,
                                          ),
                                          child: const Text(
                                            'Login',
                                            style: TextStyle(
                                              color: _formAccent,
                                              fontWeight: FontWeight.w800,
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
                                        color: AppTheme.lightTextSecondary,
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
            ],
          ),
        ),
      ),
    );
  }
}
