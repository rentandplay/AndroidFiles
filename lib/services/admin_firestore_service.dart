import 'package:firebase_auth/firebase_auth.dart';
import 'mobile_api_service.dart';
import 'notification_service.dart';

class AdminApiException implements Exception {
  const AdminApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Web and Android use the same authenticated backend and transaction rules.
class AdminFirestoreService {
  AdminFirestoreService._();
  static final AdminFirestoreService instance = AdminFirestoreService._();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Map<String, dynamic>? _user;
  bool get hasSession => _auth.currentUser != null;
  Map<String, dynamic>? get currentUser => _user;

  Future<Map<String, dynamic>> signIn(
      {required String email,
      required String password,
      bool remember = false}) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: password);
      return await restoreAdminSession();
    } on FirebaseAuthException catch (error) {
      throw AdminApiException(_authMessage(error), statusCode: 401);
    }
  }

  Future<Map<String, dynamic>> restoreAdminSession() async {
    if (_auth.currentUser == null) {
      throw const AdminApiException('Sign in with an active operator or owner account.',
          statusCode: 401);
    }
    final result = await _remote('/auth/me');
    _user = Map<String, dynamic>.from(result['user'] as Map);
    return Map<String, dynamic>.from(_user!);
  }

  Future<void> signOut() async {
    if (_auth.currentUser != null) {
      await NotificationDevices.unregister(MobileApiService.instance);
    }
    _user = null;
    await _auth.signOut();
  }

  Future<Map<String, dynamic>> _remote(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool forceRefresh = false,
  }) async {
    try {
      return await MobileApiService.instance.adminRequest(path,
          method: method, body: body, forceRefresh: forceRefresh);
    } on MobileApiException catch (error) {
      throw AdminApiException(error.message, statusCode: error.statusCode);
    } catch (_) {
      throw const AdminApiException(
          'Could not reach the rental service. Check your connection and refresh.',
          statusCode: 503);
    }
  }

  Future<Map<String, dynamic>> loadWorkspace({bool forceRefresh = false}) =>
      _remote('/mobile/admin-workspace', forceRefresh: forceRefresh);

  Map<String, dynamic> dashboardFromWorkspace(Map<String, dynamic> workspace) =>
      Map<String, dynamic>.from(workspace['_dashboard'] as Map);
  Map<String, dynamic> inventoryFromWorkspace(Map<String, dynamic> workspace) =>
      Map<String, dynamic>.from(workspace['_inventory'] as Map);
  Future<Map<String, dynamic>> getMap(String path, {bool forceRefresh = false}) =>
      _remote(path, forceRefresh: forceRefresh);
  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic> body = const {}}) =>
      _remote(path, method: 'POST', body: body);
  Future<Map<String, dynamic>> put(String path,
          {Map<String, dynamic> body = const {}}) =>
      _remote(path, method: 'PUT', body: body);
  Future<Map<String, dynamic>> patch(String path,
          {Map<String, dynamic> body = const {}}) =>
      _remote(path, method: 'PATCH', body: body);
  Future<Map<String, dynamic>> delete(String path,
          {Map<String, dynamic> body = const {}}) =>
      _remote(path, method: 'DELETE', body: body);

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' => 'Enter a valid email address.',
        'user-disabled' =>
          'This Firebase account is disabled. Contact an administrator.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'network-request-failed' =>
          'Could not reach Firebase Authentication. Check your connection and try again.',
        'requires-recent-login' =>
          'Sign out and sign in again before changing this account detail.',
        _ => error.message ??
            'Firebase Authentication could not complete this action.',
      };
}
