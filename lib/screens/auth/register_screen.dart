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
import 'id_verification_screen.dart';
import 'login_screen.dart';
import '../shared/terms_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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
  String? _emailDomainError;

  String get _currentEmail => _emailController.text.toLowerCase();
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
    if (_emailDomainError != null) setState(() => _emailDomainError = null);
    if (_verificationToken.isEmpty || _requestedEmail == _currentEmail) return;
    setState(() {
      _verificationToken = '';
      _emailVerified = false;
    });
  }

  String? _validateName(String? value, String label) {
    return AccountValidation.name(value, label: label, max: 60);
  }

  String? _validateEmail(String? value) {
    return AccountValidation.email(value) ?? _emailDomainError;
  }

  String? _validatePhone(String? value) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return 'Enter your phone number.';
    if (!RegExp(r'^[+0-9() .-]+$').hasMatch(phone)) {
      return 'Use numbers and standard phone separators only.';
    }
    final compact = phone.replaceAll(RegExp(r'[\s().-]'), '');
    if (!RegExp(r'^(?:\+?63|0)?9\d{9}$').hasMatch(compact)) {
      return 'Enter a valid Philippine mobile number.';
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
    return AccountValidation.password(value);
  }

  String? _validateCode(String? value) {
    if (!_codeMatchesCurrentEmail) return 'Send a code to this email first.';
    if (value == null || !RegExp(r'^\d{6}$').hasMatch(value)) {
      return 'Enter the 6-digit code.';
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
      _showMessage('We sent a verification code to $email.');
    } catch (error) {
      if (!mounted) return;
      if (error is MobileApiException && error.code == 'INVALID_EMAIL_DOMAIN') {
        setState(() => _emailDomainError = error.userMessage);
        _formKey.currentState?.validate();
      }
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
    if (!RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim())) {
      _showMessage('Enter the 6-digit code from your email.', isError: true);
      return;
    }
    final email = _currentEmail;
    final code = _codeController.text.trim();
    setState(() => _isVerifyingCode = true);
    try {
      final proof = await MobileApiService.instance.verifyRegistrationEmailCode(
        email: email,
        code: code,
      );
      if (!mounted) return;
      if (_currentEmail != email || _requestedEmail != email) {
        _showMessage(
            'The email changed. Send a new code to verify this address.',
            isError: true);
        return;
      }
      _resendTimer?.cancel();
      setState(() {
        _verificationToken = proof;
        _emailVerified = true;
        _resendSeconds = 0;
      });
      _showMessage('Email verified. You can create your account.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(_errorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  Future<void> _handleRegister() async {
    if (!_acceptedTerms) {
      _showMessage('Read and accept the Terms & Conditions before signing up.',
          isError: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!_verifiedCurrentEmail) {
      _showMessage('Verify your email before creating your account.',
          isError: true);
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
        termsVersion: rentalTermsVersion,
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

  Future<void> _showTerms() async {
    await TermsDialog.show(context, onAccept: () {
      if (mounted) setState(() => _acceptedTerms = true);
    }, onDecline: () {
      if (mounted) setState(() => _acceptedTerms = false);
    });
  }

  String _errorMessage(Object error) {
    if (error is MobileApiException) return error.userMessage;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'This email address is already registered. Please log in instead.';
        case 'weak-password':
          return 'Choose a stronger password and try again.';
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'operation-not-allowed':
          return 'Email and password sign-up is not enabled. Contact support.';
        case 'network-request-failed':
          return 'Connection failed. Check your internet and try again.';
        default:
          return error.message ??
              'We could not create your account. Please try again.';
      }
    }
    return 'We could not complete registration. Please try again.';
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppTheme.brandNavy,
      ));
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
      );

  InputDecoration _decoration(String hint, IconData icon,
          {Widget? suffixIcon}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.brandOrange, size: 20),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        filled: true,
        fillColor: const Color(0xFFF6F7FA),
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
          borderSide: const BorderSide(color: AppTheme.brandOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      );

  Widget _nameField(
          {required String label, required TextEditingController controller}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          TextFormField(
            controller: controller,
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            autofillHints: label == 'First name'
                ? const [AutofillHints.givenName]
                : const [AutofillHints.familyName],
            decoration: _decoration(label, Icons.person_outline),
            validator: (value) => _validateName(value, label.toLowerCase()),
          ),
        ],
      );

  Widget _nameFields(double width) {
    final first =
        _nameField(label: 'First name', controller: _firstNameController);
    final last =
        _nameField(label: 'Last name', controller: _lastNameController);
    if (width < 360) {
      return Column(children: [first, const SizedBox(height: 12), last]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 10),
        Expanded(child: last),
      ],
    );
  }

  Widget _buildHeader() => SizedBox(
        height: 246,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: IconButton(
                  tooltip: 'Go back',
                  onPressed: () => Navigator.maybePop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withAlpha(31),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 100,
                      child: Image.asset(
                        'assets/images/logo_rent_and_play.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Play More. Rent Smarter.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildRegistrationCard(double width) => Transform.translate(
        offset: const Offset(0, -18),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppTheme.brandOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'GET STARTED',
                      style: TextStyle(
                        color: AppTheme.brandOrange,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create your account',
                  style: TextStyle(
                    color: AppTheme.brandNavy,
                    fontSize: 23,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Add a few details to start renting.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 20),
                _nameFields(width),
                const SizedBox(height: 14),
                _fieldLabel('Email address'),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    const LowercaseEmailFormatter(),
                    LengthLimitingTextInputFormatter(254)
                  ],
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration:
                      _decoration('name@example.com', Icons.mail_outline),
                  validator: _validateEmail,
                ),
                if (_verifiedCurrentEmail) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F5EC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Color(0xFF16824B), size: 17),
                        SizedBox(width: 8),
                        Text(
                          'Email verified',
                          style: TextStyle(
                            color: Color(0xFF16824B),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
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
                              (_codeMatchesCurrentEmail && _resendSeconds > 0)
                          ? null
                          : _sendVerificationCode,
                      icon: _isSendingCode
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mark_email_unread_outlined,
                              size: 16),
                      label: Text(_codeMatchesCurrentEmail && _resendSeconds > 0
                          ? 'Resend in ${_resendSeconds}s'
                          : _codeMatchesCurrentEmail
                              ? 'Resend code'
                              : 'Send verification code'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.brandOrange,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
                if (_codeMatchesCurrentEmail && !_verifiedCurrentEmail) ...[
                  const SizedBox(height: 2),
                  _fieldLabel('6-digit email code'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _codeController,
                          enabled: !_isLoading,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          decoration: _decoration(
                              'Enter your code', Icons.verified_user_outlined),
                          validator: _validateCode,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _isVerifyingCode ? null : _verifyEmailCode,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.brandNavy,
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isVerifyingCode
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Verify'),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'The code expires in 10 minutes.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _fieldLabel('Phone number'),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[+0-9() .-]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration:
                      _decoration('09XX XXX XXXX', Icons.phone_outlined),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 14),
                _fieldLabel('Password'),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [LengthLimitingTextInputFormatter(128)],
                  autofillHints: const [AutofillHints.newPassword],
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: _decoration(
                      '8+ chars, one capital letter, and a number',
                      Icons.lock_outline,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                      )),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 14),
                _fieldLabel('Confirm password'),
                TextFormField(
                  controller: _confirmPasswordController,
                  enabled: !_isLoading,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [LengthLimitingTextInputFormatter(128)],
                  autofillHints: const [AutofillHints.newPassword],
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: _decoration(
                      'Re-enter your password', Icons.lock_outline,
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirmPassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(() =>
                            _obscureConfirmPassword = !_obscureConfirmPassword),
                        icon: Icon(_obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                      )),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirm your password.';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        activeColor: AppTheme.brandOrange,
                        onChanged: _isLoading
                            ? null
                            : (value) => setState(
                                  () => _acceptedTerms = value ?? false,
                                ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'I have read and agree to the ',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                              GestureDetector(
                                onTap: _isLoading ? null : _showTerms,
                                child: const Text(
                                  'Terms & Conditions',
                                  style: TextStyle(
                                    color: AppTheme.brandOrange,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              const Text(
                                ' before creating my account.',
                                style: TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 12,
                                  height: 1.5,
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
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brandOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    onPressed: _isLoading || !_acceptedTerms
                        ? null
                        : _handleRegister,
                    icon: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_forward, size: 19),
                    label: Text(
                      _isLoading ? 'Creating account…' : 'Create account',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ',
                        style:
                            TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: AppTheme.brandOrange,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: AppTheme.brandNavy,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            children: [
              _buildHeader(),
              _buildRegistrationCard(width),
            ],
          ),
        ),
      ),
    );
  }
}
