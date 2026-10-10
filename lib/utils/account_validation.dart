import 'package:flutter/services.dart';

class LowercaseEmailFormatter extends TextInputFormatter {
  const LowercaseEmailFormatter();
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toLowerCase());
}

class AccountValidation {
  static const passwordHelp =
      'Use 8+ characters, one capital letter, and one number.';

  static String? email(String? value) {
    final email = (value ?? '').toLowerCase();
    if (email.isEmpty) return 'Enter your email address.';
    if (RegExp(r'\s').hasMatch(email))
      return 'Email addresses cannot contain spaces.';
    final parts = email.split('@');
    if (email.length > 254 ||
        parts.length != 2 ||
        parts.first.isEmpty ||
        parts.first.length > 64) return 'Enter a valid email address.';
    if (!RegExp(
            r"^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*$")
        .hasMatch(parts.first)) return 'Enter a valid email address.';
    final labels = parts.last.split('.');
    if (parts.last.length > 253 ||
        labels.length < 2 ||
        !labels.every((label) =>
            RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
                .hasMatch(label)) ||
        !RegExp(r'^(?:[a-z]{2,63}|xn--[a-z0-9-]+)$').hasMatch(labels.last))
      return 'Enter a valid email address.';
    return null;
  }

  static String? name(String? value,
      {String label = 'full name', int max = 150}) {
    final name = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return 'Enter your $label.';
    if (name.length > max) return 'Use $max characters or fewer.';
    if (!name.split(' ').every((word) => RegExp(
            r"^[\p{L}\p{M}]+(?:['\u2019.\-][\p{L}\p{M}]+)*\.?$",
            unicode: true)
        .hasMatch(word)))
      return 'Use letters, spaces, apostrophes, or hyphens only.';
    final words = name.split(' ');
    int letters(String word) =>
        RegExp(r'\p{L}', unicode: true).allMatches(word).length;
    if (letters(words.first) < 2 || letters(words.last) < 2)
      return 'Use at least 2 letters for each name.';
    if (RegExp(r'([\p{L}])\1{3,}', unicode: true, caseSensitive: false)
        .hasMatch(name))
      return 'Enter your real name without repeated character strings.';
    return null;
  }

  static String? password(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter a password.';
    if (password.length < 8 ||
        password.length > 128 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) return passwordHelp;
    return null;
  }

  static String? passwordMatch(String password, String? confirmation) {
    if (confirmation == null || confirmation.isEmpty)
      return 'Confirm your password.';
    return password == confirmation ? null : 'Passwords do not match.';
  }

  static String? phone(String? value, {bool required = true}) {
    final phone = (value ?? '').trim();
    if (phone.isEmpty) return required ? 'Enter your phone number.' : null;
    return RegExp(r'^[+0-9() .-]+$').hasMatch(phone) &&
            RegExp(r'^(?:\+?63|0)?9\d{9}$')
                .hasMatch(phone.replaceAll(RegExp(r'[\s().-]'), ''))
        ? null
        : 'Enter a valid Philippine mobile number.';
  }
}
