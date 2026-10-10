import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/account_validation.dart';
import 'login_screen.dart';

class RequiredPasswordChangeScreen extends StatefulWidget {
  const RequiredPasswordChangeScreen({super.key});
  @override
  State<RequiredPasswordChangeScreen> createState() =>
      _RequiredPasswordChangeScreenState();
}

class _RequiredPasswordChangeScreenState
    extends State<RequiredPasswordChangeScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false, _show = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _login() => Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().changeTemporaryPassword(
          currentPassword: _current.text,
          newPassword: _password.text,
          confirmation: _confirmation.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      _login();
      messenger.showSnackBar(const SnackBar(
          content: Text('Password updated. Log in with your new password.')));
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is MobileApiException
            ? error.userMessage
            : 'Could not update your password. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: false,
      child: Scaffold(
          appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Secure your account'),
              actions: [
                TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await context.read<AuthService>().logout();
                            if (mounted) _login();
                          },
                    child: const Text('Sign out'))
              ]),
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Form(
                          key: _form,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(Icons.lock_reset, size: 54),
                                const SizedBox(height: 20),
                                const Text('Choose your own password',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                const Text(
                                    'Change the temporary password before opening your Owner or Operator workspace.'),
                                const SizedBox(height: 24),
                                TextFormField(
                                    controller: _current,
                                    enabled: !_busy,
                                    obscureText: !_show,
                                    autofillHints: const [
                                      AutofillHints.password
                                    ],
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Current / temporary password',
                                        border: OutlineInputBorder()),
                                    validator: (value) => value == null ||
                                            value.isEmpty
                                        ? 'Enter your current or temporary password.'
                                        : null),
                                const SizedBox(height: 18),
                                TextFormField(
                                    controller: _password,
                                    enabled: !_busy,
                                    obscureText: !_show,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(128)
                                    ],
                                    autofillHints: const [
                                      AutofillHints.newPassword
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'New password',
                                        helperText:
                                            AccountValidation.passwordHelp,
                                        helperMaxLines: 2,
                                        border: OutlineInputBorder()),
                                    validator: (value) =>
                                        AccountValidation.password(value) ??
                                        (value == _current.text
                                            ? 'Choose a different password.'
                                            : null)),
                                const SizedBox(height: 18),
                                TextFormField(
                                    controller: _confirmation,
                                    enabled: !_busy,
                                    obscureText: !_show,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(128)
                                    ],
                                    decoration: const InputDecoration(
                                        labelText: 'Confirm new password',
                                        border: OutlineInputBorder()),
                                    validator: (value) =>
                                        AccountValidation.passwordMatch(
                                            _password.text, value)),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Show passwords'),
                                    value: _show,
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                            setState(() => _show = value)),
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
                                    onPressed: _busy ? null : _save,
                                    child: _busy
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
                                                Text('Updating password…')
                                              ])
                                        : const Text('Update password')),
                              ])))))));
}
