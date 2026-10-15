import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/mobile_api_service.dart';
import '../../utils/account_validation.dart';

enum _ResetStep { email, code, password, complete }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = '', this.api});
  final String initialEmail;
  final MobileApiService? api;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  _ResetStep _step = _ResetStep.email;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _verifiedEmail;
  String? _verificationToken;
  String? _requestKey;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  MobileApiService get _api => widget.api ?? MobileApiService.instance;

  @override
  void initState() {
    super.initState();
    _email =
        TextEditingController(text: widget.initialEmail.trim().toLowerCase());
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (_busy || (!resend && !_formKey.currentState!.validate())) return;
    final address = _email.text.trim().toLowerCase();
    final validation = AccountValidation.email(address);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.requestPasswordResetCode(address);
      if (!mounted) return;
      setState(() {
        _verifiedEmail = address;
        _step = _ResetStep.code;
        _code.clear();
        _verificationToken = null;
        _requestKey = null;
        _error = null;
      });
      _startResendCooldown();
    } on MobileApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not send the verification email. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
    final value = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _api.verifyPasswordResetCode(_verifiedEmail!, value);
      final token = result['verificationToken'];
      if (token is! String || token.length < 32) {
        throw const MobileApiException(
            'Could not verify that code. Request a new one.');
      }
      if (!mounted) return;
      setState(() {
        _verificationToken = token;
        _requestKey = MobileApiService.operationKey();
        _step = _ResetStep.password;
        _error = null;
      });
    } on MobileApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not verify the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePassword() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.completePasswordReset(
        email: _verifiedEmail!,
        verificationToken: _verificationToken!,
        requestKey: _requestKey!,
        newPassword: _password.text,
        confirmPassword: _confirmation.text,
      );
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _step = _ResetStep.complete;
        _verificationToken = null;
        _requestKey = null;
        _password.clear();
        _confirmation.clear();
        _error = null;
      });
    } on MobileApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not update your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _editEmail() {
    _restart();
  }

  void _restart() {
    _resendTimer?.cancel();
    setState(() {
      _step = _ResetStep.email;
      _code.clear();
      _verificationToken = null;
      _requestKey = null;
      _password.clear();
      _confirmation.clear();
      _resendSeconds = 0;
      _error = null;
    });
  }

  String get _stepTitle => switch (_step) {
        _ResetStep.email => 'Reset your password',
        _ResetStep.code => 'Verify your email',
        _ResetStep.password => 'Choose a new password',
        _ResetStep.complete => 'Password updated',
      };

  Widget _progress(BuildContext context) {
    const labels = ['Email', 'Code', 'Password'];
    final current = _step.index.clamp(0, 2);
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: index <= current
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  foregroundColor: index <= current
                      ? colors.onPrimary
                      : colors.onSurfaceVariant,
                  child: Text('${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 7),
                Text(labels[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: index == current
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontWeight: index == current
                              ? FontWeight.w700
                              : FontWeight.w500,
                        )),
              ],
            ),
          ),
          if (index < labels.length - 1)
            Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 19),
                child: Divider(
                  color:
                      index < current ? colors.primary : colors.outlineVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _emailForm(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_unread_outlined,
              size: 42, color: colors.primary),
          const SizedBox(height: 18),
          Text('Enter your account email',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 8),
          Text(
            'We’ll send a one-time code to verify it’s you before you choose a new password.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            inputFormatters: [
              const LowercaseEmailFormatter(),
              LengthLimitingTextInputFormatter(254),
            ],
            decoration: const InputDecoration(
              labelText: 'Account email',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: AccountValidation.email,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _errorBox(context, _error!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _sendCode,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_busy ? 'Sending code…' : 'Send verification code'),
          ),
        ],
      ),
    );
  }

  Widget _codeForm(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 42, color: colors.primary),
        const SizedBox(height: 18),
        Text('Enter your verification code',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 8),
        Text(
          'If an active account exists for $_verifiedEmail, a code has been sent. Check your inbox and spam folder.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            letterSpacing: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: const InputDecoration(
            labelText: '6-digit email code',
            hintText: '000000',
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (_) => _verifyCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _errorBox(context, _error!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _verifyCode,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify code'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy || _resendSeconds > 0
              ? null
              : () => _sendCode(resend: true),
          child: Text(_resendSeconds > 0
              ? 'Resend code in ${_resendSeconds}s'
              : 'Resend code'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _editEmail,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Use a different email'),
        ),
      ],
    );
  }

  Widget _passwordForm(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_reset_outlined, size: 42, color: colors.primary),
          const SizedBox(height: 18),
          Text('Choose a new password',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 8),
          Text(
            'Your email is verified. Create a new password for $_verifiedEmail.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            inputFormatters: [LengthLimitingTextInputFormatter(128)],
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: AccountValidation.passwordHelp,
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            validator: AccountValidation.password,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmation,
            enabled: !_busy,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.newPassword],
            inputFormatters: [LengthLimitingTextInputFormatter(128)],
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                AccountValidation.passwordMatch(_password.text, value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show passwords'),
            value: _showPassword,
            onChanged:
                _busy ? null : (value) => setState(() => _showPassword = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _errorBox(context, _error!),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _savePassword,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update password'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _restart,
            icon: const Icon(Icons.restart_alt_outlined, size: 18),
            label: const Text('Start over'),
          ),
        ],
      ),
    );
  }

  Widget _complete(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline, size: 54, color: colors.primary),
        const SizedBox(height: 18),
        Text('Your password has been updated',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 10),
        Text('Sign in with your new password to continue.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                )),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _errorBox(BuildContext context, String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Account recovery')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_step != _ResetStep.complete) ...[
                          _progress(context),
                          const SizedBox(height: 26),
                        ],
                        Text(_stepTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 22),
                        switch (_step) {
                          _ResetStep.email => _emailForm(context),
                          _ResetStep.code => _codeForm(context),
                          _ResetStep.password => _passwordForm(context),
                          _ResetStep.complete => _complete(context),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
