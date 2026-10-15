import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/screens/auth/forgot_password_screen.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'widget_test.dart' show SignedOutAuth;

class RecoveryApi extends MobileApiService {
  final requests = <String>[];
  final verifiedCodes = <String>[];
  final completions = <Map<String, String>>[];
  bool failCompletion = false;

  @override
  Future<Map<String, dynamic>> requestPasswordResetCode(String email) async {
    requests.add(email);
    return {};
  }

  @override
  Future<Map<String, dynamic>> verifyPasswordResetCode(
      String email, String code) async {
    verifiedCodes.add(code);
    if (code != '123456') {
      throw const MobileApiException('Invalid or expired code.');
    }
    return {
      'verificationToken': 'verified-token-012345678901234567890123456789'
    };
  }

  @override
  Future<Map<String, dynamic>> completePasswordReset({
    required String email,
    required String verificationToken,
    required String requestKey,
    required String newPassword,
    required String confirmPassword,
  }) async {
    completions.add({
      'email': email,
      'verificationToken': verificationToken,
      'requestKey': requestKey,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    });
    if (failCompletion) {
      throw const MobileApiException('Connection interrupted. Please retry.');
    }
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });

  Future<void> field(WidgetTester tester, String label, String value) async {
    final target = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
  }

  Future<void> press(WidgetTester tester, String label) async {
    final target = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> reachPassword(WidgetTester tester, RecoveryApi api) async {
    await tester.pumpWidget(MaterialApp(
        home:
            ForgotPasswordScreen(api: api, initialEmail: 'ANA@example.test')));
    await press(tester, 'Send verification code');
    await field(tester, '6-digit email code', '123456');
    await press(tester, 'Verify code');
  }

  testWidgets('email OTP gates password reset and matching passwords succeed',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = RecoveryApi();
    await tester.pumpWidget(MaterialApp(
        home:
            ForgotPasswordScreen(api: api, initialEmail: 'ANA@example.test')));
    expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
    await press(tester, 'Send verification code');
    expect(api.requests, ['ana@example.test']);
    await field(tester, '6-digit email code', '000000');
    await press(tester, 'Verify code');
    expect(find.text('Invalid or expired code.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'New password'), findsNothing);
    await field(tester, '6-digit email code', '123456');
    await press(tester, 'Verify code');
    await field(tester, 'New password', 'BetterPass9');
    await field(tester, 'Confirm new password', 'DifferentPass9');
    await press(tester, 'Update password');
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(api.completions, isEmpty);
    await field(tester, 'Confirm new password', 'BetterPass9');
    await press(tester, 'Update password');
    expect(api.completions.single['newPassword'], 'BetterPass9');
    expect(api.completions.single['confirmPassword'], 'BetterPass9');
    expect(api.completions.single['email'], 'ana@example.test');
    expect(find.text('Your password has been updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'reset retry preserves its operation key and restart clears secrets',
      (tester) async {
    final api = RecoveryApi()..failCompletion = true;
    await reachPassword(tester, api);
    await field(tester, 'New password', 'BetterPass9');
    await field(tester, 'Confirm new password', 'BetterPass9');
    await press(tester, 'Update password');
    expect(find.text('Connection interrupted. Please retry.'), findsOneWidget);
    await press(tester, 'Update password');
    expect(api.completions, hasLength(2));
    expect(api.completions[0]['requestKey'], isNotEmpty);
    expect(api.completions[1]['requestKey'], api.completions[0]['requestKey']);
    final restart = find.text('Start over');
    await tester.ensureVisible(restart);
    await tester.tap(restart);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Account email'), findsOneWidget);
    await press(tester, 'Send verification code');
    await field(tester, '6-digit email code', '123456');
    await press(tester, 'Verify code');
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.every((field) => field.controller!.text.isEmpty), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
