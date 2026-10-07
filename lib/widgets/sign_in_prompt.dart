import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';

enum _AuthenticationChoice { login, register }

Future<void> showSignInPrompt(BuildContext context) async {
  final choice = await showDialog<_AuthenticationChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Sign in to rent'),
      content: const Text(
        'Log in or create an account to continue with this rental.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_AuthenticationChoice.login),
          child: const Text('Log in'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_AuthenticationChoice.register),
          child: const Text('Create account'),
        ),
      ],
    ),
  );

  if (!context.mounted || choice == null) return;

  final screen = switch (choice) {
    _AuthenticationChoice.login => const LoginScreen(),
    _AuthenticationChoice.register => const RegisterScreen(),
  };
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => screen),
  );
}
