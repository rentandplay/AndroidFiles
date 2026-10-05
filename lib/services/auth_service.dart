import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register with Email and Password
  Future<UserModel?> registerWithEmailAndPassword({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    try {
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user != null) {
        final newUser = UserModel(
          uid: credential.user!.uid,
          name: name.trim(),
          email: email.trim(),
          phone: phone.trim(),
          role: 'user',
          hasAcceptedTerms: false,
          createdAt: DateTime.now(),
        );

        await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(newUser.toMap(), SetOptions(merge: true));

        notifyListeners();
        return newUser;
      }
    } catch (e) {
      debugPrint('Registration Error: $e');
      rethrow;
    }
    return null;
  }

  // Login with Email and Password
  Future<UserCredential> loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .get();
        if (!userDoc.exists) {
          final newUser = UserModel(
            uid: credential.user!.uid,
            name: credential.user!.displayName ?? email.split('@').first,
            email: email.trim(),
            phone: credential.user!.phoneNumber ?? '',
            role: 'user',
            hasAcceptedTerms: false,
            createdAt: DateTime.now(),
          );
          await _firestore
              .collection('users')
              .doc(credential.user!.uid)
              .set(newUser.toMap(), SetOptions(merge: true));
        }
      }

      notifyListeners();
      return credential;
    } catch (e) {
      debugPrint('Login Error: $e');
      rethrow;
    }
  }

  // Google Sign-In
  Future<UserModel?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        DocumentSnapshot doc =
            await _firestore.collection('users').doc(user.uid).get();

        if (!doc.exists) {
          final newUser = UserModel(
            uid: user.uid,
            name: user.displayName ?? 'Rental Customer',
            email: user.email ?? '',
            phone: user.phoneNumber ?? '',
            role: 'user',
            hasAcceptedTerms: false,
            createdAt: DateTime.now(),
          );
          await _firestore
              .collection('users')
              .doc(user.uid)
              .set(newUser.toMap(), SetOptions(merge: true));
          notifyListeners();
          return newUser;
        } else {
          notifyListeners();
          return UserModel.fromMap(doc.data() as Map<String, dynamic>,
              uid: doc.id);
        }
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
    return null;
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
    notifyListeners();
  }

  // Fetch Current User Profile Model
  Future<UserModel?> getCurrentUserModel() async {
    User? user = _auth.currentUser;
    if (user == null) return null;

    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>,
            uid: doc.id);
      } else {
        final fallbackUser = UserModel(
          uid: user.uid,
          name: user.displayName ??
              user.email?.split('@').first ??
              'Rental Customer',
          email: user.email ?? '',
          phone: user.phoneNumber ?? '',
          role: 'user',
          hasAcceptedTerms: false,
          createdAt: DateTime.now(),
        );
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(fallbackUser.toMap(), SetOptions(merge: true));
        return fallbackUser;
      }
    } catch (e) {
      debugPrint('Fetch User Model Error: $e');
      return UserModel(
        uid: user.uid,
        name: user.displayName ??
            user.email?.split('@').first ??
            'Rental Customer',
        email: user.email ?? '',
        phone: user.phoneNumber ?? '',
        role: 'user',
        hasAcceptedTerms: false,
        createdAt: DateTime.now(),
      );
    }
  }

  // Stream User Profile
  Stream<UserModel?> streamUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>,
            uid: doc.id);
      }
      return null;
    });
  }

  // Update Valid ID URL
  Future<void> updateValidIdUrl(String uid, String validIdUrl) async {
    await _firestore.collection('users').doc(uid).set({
      'validIdUrl': validIdUrl,
    }, SetOptions(merge: true));
    notifyListeners();
  }

  // Update Terms Acceptance
  Future<void> updateTermsAcceptance(String uid, bool accepted) async {
    await _firestore.collection('users').doc(uid).set({
      'hasAcceptedTerms': accepted,
    }, SetOptions(merge: true));
    notifyListeners();
  }
}
