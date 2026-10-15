import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/screens/auth/login_screen.dart';
import 'package:rent_and_play_app/screens/auth/register_screen.dart';
import 'package:rent_and_play_app/utils/account_validation.dart';
import 'package:rent_and_play_app/models/user_model.dart';

void main() {
  test(
      'validation rejects reported junk and accepts legitimate names and emails',
      () {
    for (final name in [
      'A',
      'A B',
      'Juan123 Santos',
      'Juan @ Santos',
      'raveeeeeeNN hwidawgiodgawqqqqqqqqq'
    ]) {
      expect(AccountValidation.name(name), isNotNull);
    }
    for (final name in [
      'José Dela Cruz',
      'Anne-Marie O’Neill',
      'Maria J. Santos',
      '李明 王伟'
    ]) {
      expect(AccountValidation.name(name), isNull);
    }
    for (final email in [
      'some one@gmail.com',
      ' test@gmail.com',
      'test..name@gmail.com',
      'user@-domain.com'
    ]) {
      expect(AccountValidation.email(email), isNotNull);
    }
    expect(AccountValidation.email('Maria@school.edu.ph'), isNull);
    expect(AccountValidation.email('first.last+tag@company.com'), isNull);
    for (final password in ['shortA1', 'alllowercase9', 'NoNumbersHere']) {
      expect(AccountValidation.password(password), isNotNull);
    }
    expect(AccountValidation.password('ABCDEF12'), isNull);
    expect(AccountValidation.passwordMatch('StrongPass8', 'Different8'),
        isNotNull);
  });
  test(
      'legacy roles normalize and password-change state survives profile loading',
      () {
    final staff = UserModel.fromMap(
        {'uid': 'staff', 'role': 'ADMIN', 'mustChangePassword': true});
    expect(staff.role, 'OPERATOR');
    expect(staff.isStaff, isTrue);
    expect(staff.mustChangePassword, isTrue);
    expect(UserModel.fromMap({'role': 'USER'}).role, 'CUSTOMER');
  });
  testWidgets(
      'mobile login validates only on submit and forgot password asks for an address',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final email = find.byType(TextFormField).first;
    final login = find.widgetWithText(ElevatedButton, 'Login');
    await tester.enterText(email, 'reynold');
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsNothing);
    expect(find.text('Please enter your password.'), findsNothing);
    await tester.enterText(email, 'some one@school.edu.ph');
    await tester.pump();
    expect(find.text('Email addresses cannot contain spaces.'), findsNothing);
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.text('Email addresses cannot contain spaces.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);
    await tester.enterText(email, 'MARIA@SCHOOL.EDU.PH');
    await tester.pump();
    expect(tester.widget<TextFormField>(email).controller!.text,
        'maria@school.edu.ph');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.text('Email addresses cannot contain spaces.'), findsNothing);
    expect(find.text('Please enter your password.'), findsOneWidget);
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Account email'), findsOneWidget);
    expect(find.text('Send verification code'), findsOneWidget);
    expect(find.text('Password reset link sent to your email.'), findsNothing);
  });
  testWidgets(
      'registration keeps untouched fields quiet and validates fields as edited',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    final fields = find.byType(TextFormField);
    expect(find.text('Enter your first name.'), findsNothing);
    expect(find.text('Enter your email address.'), findsNothing);
    expect(find.text('Enter your phone number.'), findsNothing);
    expect(find.text('Enter a password.'), findsNothing);
    await tester.enterText(fields.at(0), 'A');
    await tester.pump();
    expect(find.text('Use at least 2 letters for each name.'), findsWidgets);
    expect(find.text('Enter your email address.'), findsNothing);
    expect(find.text('Enter your phone number.'), findsNothing);
    await tester.enterText(fields.at(0), 'raveeeeeeNN');
    await tester.pump();
    expect(
        find.text('Enter your real name without repeated character strings.'),
        findsOneWidget);
  });
}
