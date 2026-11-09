import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:rent_and_play_app/services/admin_firestore_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/utils/error_sanitizer.dart';

void main() {
  group('ErrorSanitizer', () {
    test('masks technical database and firebase traces', () {
      final technical = Exception('FirebaseError: [firestore/unavailable] The database is unreachable');
      final result = ErrorSanitizer.format(technical);
      expect(result, isNot(contains('FirebaseError')));
      expect(result, isNot(contains('firestore')));
      expect(result, isNot(contains('database is unreachable')));
    });

    test('masks raw socket and host lookup network errors', () {
      final socket = Exception('SocketException: OS Error: Connection refused, errno = 111, address = 127.0.0.1');
      final result = ErrorSanitizer.format(socket);
      expect(result, 'Unable to connect to the server. Please check your internet connection and try again.');
    });

    test('formats MobileApiException userMessage accurately', () {
      const apiEx = MobileApiException('Unable to reach server', code: 'FIREBASE_UNAVAILABLE');
      final result = ErrorSanitizer.format(apiEx);
      expect(result, 'The rental service is temporarily unavailable. Please try again later.');
    });

    test('formats PlatformException for cancellation cleanly', () {
      final platformEx = PlatformException(code: 'sign_in_canceled', message: 'User aborted');
      final result = ErrorSanitizer.format(platformEx);
      expect(result, 'Sign-in was cancelled.');
    });

    test('protects AdminApiException from leaking backend stack traces', () {
      const adminEx = AdminApiException('PGRST: database failed at apps/backend/src/server.mjs:42');
      final result = ErrorSanitizer.format(adminEx);
      expect(result, isNot(contains('apps/backend')));
      expect(result, isNot(contains('PGRST')));
    });
  });
}
