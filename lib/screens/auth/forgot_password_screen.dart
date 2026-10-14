import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/account_validation.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});
  final String initialEmail;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _sending = false;
  String? _requestedEmail, _error, _emailError;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail.toLowerCase());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    final email = _email.text;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await MobileApiService.instance.requestPasswordReset(email);
      if (mounted) setState(() => _requestedEmail = email);
    } on MobileApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.userMessage;
          if (error.code == 'INVALID_EMAIL_DOMAIN') {
            _emailError = error.userMessage;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not request the reset link. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _requestedEmail != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              const Icon(Icons.mark_email_read_outlined,
                                  size: 56),
                              const SizedBox(height: 20),
                              const Text('Check your email',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              Text(
                                  'If an account exists for $_requestedEmail, a password-reset link has been requested for that address.'),
                              const SizedBox(height: 16),
                              const Text(
                                  '1. Open the email from Rent & Play. Check your spam folder too.\n\n2. Follow the reset link and choose a new password.\n\n3. Return here and log in with your new password.'),
                              const SizedBox(height: 24),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Back to login')),
                              TextButton(
                                  onPressed: () => setState(() {
                                        _requestedEmail = null;
                                        _emailError = null;
                                      }),
                                  child: const Text('Use another email')),
                            ])
                      : Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Forgot your password?',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                const Text(
                                    'Enter the email registered to your account. Tap Send reset link to request an email with the next steps.'),
                                const SizedBox(height: 24),
                                TextFormField(
                                    controller: _email,
                                    enabled: !_sending,
                                    keyboardType: TextInputType.emailAddress,
                                    autocorrect: false,
                                    textCapitalization: TextCapitalization.none,
                                    inputFormatters: [
                                      const LowercaseEmailFormatter(),
                                      LengthLimitingTextInputFormatter(254)
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'Account email',
                                        hintText: 'name@example.com',
                                        border: OutlineInputBorder()),
                                    onChanged: (_) =>
                                        setState(() => _emailError = null),
                                    validator: (value) =>
                                        AccountValidation.email(value) ??
                                        _emailError),
                                const SizedBox(height: 16),
                                if (_error != null)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Text(_error!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                                FilledButton(
                                    onPressed: _sending ? null : _send,
                                    child: _sending
                                        ? const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                                SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2)),
                                                SizedBox(width: 10),
                                                Text('Sending reset link…')
                                              ])
                                        : const Text('Send reset link')),
                              ]))))));
}
