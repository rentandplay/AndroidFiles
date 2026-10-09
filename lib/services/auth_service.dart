import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import 'mobile_api_service.dart';
import 'notification_service.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    _subscription = _auth.authStateChanges().listen((_) => notifyListeners());
  }
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _api = MobileApiService.instance;
  late final StreamSubscription<User?> _subscription;
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> registerWithEmailAndPassword(
      {required String name,
      required String email,
      required String password,
      required String phone}) async {
    await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    final result = await _api.profile(
        method: 'POST', body: {'name': name.trim(), 'phone': phone.trim()});
    notifyListeners();
    return UserModel.fromMap(Map<String, dynamic>.from(result['user'] as Map),
        uid: currentUser!.uid);
  }

  Future<UserCredential> loginWithEmailAndPassword(
      {required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    await _api.profile(method: 'POST', body: {});
    notifyListeners();
    return credential;
  }

  Future<UserModel?> signInWithGoogle() async {
    if (kIsWeb) {
      // Firebase Auth owns the browser OAuth flow and reads the Google provider
      // configuration from the Firebase project. google_sign_in's web plugin
      // needs a separate clientId, which is not configured for this app.
      await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;
      final googleAuth = await googleUser.authentication;
      await _auth.signInWithCredential(GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken));
    }
    await _api.profile(method: 'POST', body: {});
    notifyListeners();
    return getCurrentUserModel();
  }

  Future<void> logout() async {
    if (currentUser != null) await NotificationDevices.unregister(_api);
    await _auth.signOut();
    notifyListeners();
  }

  Future<UserModel?> getCurrentUserModel() async {
    final user = currentUser;
    if (user == null) return null;
    final result = await _api.profile();
    return UserModel.fromMap(Map<String, dynamic>.from(result['user'] as Map),
        uid: user.uid);
  }

  Stream<UserModel?> streamUserProfile(String uid) async* {
    if (currentUser?.uid != uid) {
      yield null;
      return;
    }
    yield await getCurrentUserModel();
    yield* Stream.periodic(const Duration(seconds: 30))
        .asyncMap((_) => getCurrentUserModel());
  }

  Future<void> updateValidIdUrl(String uid, String validIdUrl) async {
    if (currentUser?.uid != uid) {
      throw const MobileApiException('Sign in to update your profile.');
    }
    await _api.profile(method: 'PATCH', body: {'validIdUrl': validIdUrl});
    notifyListeners();
  }

  Future<void> updateTermsAcceptance(String uid, bool accepted) async {
    if (currentUser?.uid != uid) {
      throw const MobileApiException('Sign in to accept the rental terms.');
    }
    await _api.profile(method: 'PATCH', body: {'hasAcceptedTerms': accepted});
    notifyListeners();
  }

  Future<void> updateProfileImageUrl(String imageUrl) async {
    if (currentUser == null) {
      throw const MobileApiException('Sign in to update your profile picture.',
          statusCode: 401);
    }
    await _api.profile(method: 'PATCH', body: {'profileImageUrl': imageUrl});
    notifyListeners();
  }

  Future<UserModel> updateCustomerProfile({
    required String name,
    required String phone,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw const MobileApiException('Sign in again to update your profile.',
          statusCode: 401);
    }
    final result = await _api.profile(method: 'PATCH', body: {
      'name': name.trim(),
      'phone': phone.trim(),
    });
    await user.reload();
    notifyListeners();
    return UserModel.fromMap(
        Map<String, dynamic>.from(result['user'] as Map),
        uid: user.uid);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
