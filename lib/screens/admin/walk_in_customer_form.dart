import 'package:flutter/material.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/account_validation.dart';

/// Creates a directory profile; app access is an explicit, optional choice.
class WalkInCustomerForm extends StatefulWidget {
  const WalkInCustomerForm({super.key, required this.api});
  final MobileApiService api;
  @override
  State<WalkInCustomerForm> createState() => _WalkInCustomerFormState();
}

class _WalkInCustomerFormState extends State<WalkInCustomerForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _email = TextEditingController(),
      _address = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _key = MobileApiService.operationKey();
  bool _appLogin = false, _busy = false;
  String _error = '';
  @override
  void dispose() {
    for (final input in [
      _name,
      _phone,
      _email,
      _address,
      _password,
      _confirm
    ]) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final response = await widget.api.adminRequest(
          _appLogin ? '/customer-accounts' : '/customers',
          method: 'POST',
          body: {
            'fullName': _name.text.trim(),
            'phone': _phone.text.trim(),
            'email': _email.text.trim().toLowerCase(),
            'address': _address.text.trim(),
            'requestKey': _key,
            if (_appLogin) ...{
              'password': _password.text,
              'confirmPassword': _confirm.text
            },
          });
      final customer = response['customer'];
      if (customer is! Map || customer['id'] == null) {
        throw StateError('The saved customer could not be loaded.');
      }
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(customer));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('New walk-in customer'),
          content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Check the directory first to reuse an existing customer. A walk-in profile does not require an app.'),
                        TextFormField(
                            controller: _name,
                            enabled: !_busy,
                            maxLength: 150,
                            decoration:
                                const InputDecoration(labelText: 'Full name'),
                            validator: AccountValidation.name),
                        TextFormField(
                            controller: _phone,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            maxLength: 40,
                            decoration: const InputDecoration(
                                labelText: 'Philippine mobile number'),
                            validator: AccountValidation.phone),
                        TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 254,
                            decoration: const InputDecoration(
                                labelText:
                                    'Email (optional without app login)'),
                            validator: (value) =>
                                !_appLogin && (value?.trim().isEmpty ?? true)
                                    ? null
                                    : AccountValidation.email(
                                        value?.trim().toLowerCase())),
                        TextFormField(
                            controller: _address,
                            enabled: !_busy,
                            maxLength: 500,
                            decoration: const InputDecoration(
                                labelText: 'Address (optional)')),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Create mobile app access'),
                            subtitle: const Text(
                                'Optional. The customer can rent without an email or password.'),
                            value: _appLogin,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() {
                                      _appLogin = value ?? false;
                                      _password.clear();
                                      _confirm.clear();
                                    })),
                        if (_appLogin) ...[
                          TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Password',
                                  helperText: AccountValidation.passwordHelp),
                              validator: AccountValidation.password),
                          TextFormField(
                              controller: _confirm,
                              enabled: !_busy,
                              obscureText: true,
                              decoration: const InputDecoration(
                                  labelText: 'Confirm password'),
                              validator: (value) =>
                                  AccountValidation.passwordMatch(
                                      _password.text, value)),
                        ],
                        if (_error.isNotEmpty)
                          Text(_error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ])))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving…' : 'Save customer profile'))
          ],
        ),
      );
}
