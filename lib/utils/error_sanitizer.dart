import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../services/admin_firestore_service.dart';
import '../services/mobile_api_service.dart';

/// Centralized sanitizer for customer-facing and presentation-safe error messages.
/// Ensures no raw stack traces, Firebase internal identifiers, or database errors
/// leak to end-users or during demonstrations.
class ErrorSanitizer {
  static final RegExp _technicalRegex = RegExp(
    r'database|backend|firebase|firestore|postgres|sql\b|PGRST|ECONN|ENOTFOUND|'
    r'fetch failed|failed to fetch|npm run|apps[/\\]backend|service.?role|'
    r'stack trace|TypeError|SyntaxError|<html|<!doctype|127\.0\.0\.1|localhost|'
    r'https?://|\bat \w+.*:\d+:\d+|Bad state|Null check operator|Unhandled Exception|'
    r'PlatformException|NoSuchMethodError',
    caseSensitive: false,
  );

  /// Converts any exception or error object into a clean, reassuring message.
  static String format(
    Object? error, {
    String fallback = 'An unexpected error occurred. Please try again.',
  }) {
    if (error == null) return fallback;

    // Handled API exceptions from our mobile service
    if (error is MobileApiException) {
      return error.userMessage;
    }

    // Handled admin exceptions
    if (error is AdminApiException) {
      final text = error.message.trim();
      if (_technicalRegex.hasMatch(text)) {
        return 'Could not connect to the rental service. Please check your network and try again.';
      }
      return text.isNotEmpty ? text : fallback;
    }

    // Firebase Auth errors
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-email' => 'Please enter a valid email address.',
        'user-disabled' =>
          'This account has been disabled. Please contact an administrator.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Incorrect email or password. Please try again.',
        'email-already-in-use' =>
          'This email is already registered. Please log in instead.',
        'weak-password' =>
          'Password is too weak. Please use at least 6 characters.',
        'operation-not-allowed' =>
          'Sign-in is temporarily unavailable. Please try again later.',
        'network-request-failed' =>
          'Connection failed. Please check your internet connection and try again.',
        'too-many-requests' =>
          'Too many unsuccessful attempts. Please wait a few moments and try again.',
        'requires-recent-login' =>
          'Please sign in again before changing this account detail.',
        _ => fallback,
      };
    }

    // Native platform exceptions (e.g. Google Sign In cancellation or Google Play Service errors)
    if (error is PlatformException) {
      final diagnostic = '${error.code} ${error.message ?? ''}'.toLowerCase();
      if (diagnostic.contains('sign_in_canceled') ||
          diagnostic.contains('canceled') ||
          diagnostic.contains('cancelled') ||
          diagnostic.contains('abort')) {
        return 'Sign-in was cancelled.';
      }
      if (diagnostic.contains('network') ||
          diagnostic.contains('connection') ||
          diagnostic.contains('timeout')) {
        return 'Unable to connect. Please check your internet connection and try again.';
      }
      return 'Could not complete authentication. Please try again.';
    }

    final raw = error.toString();
    final lower = raw.toLowerCase();

    // Common network errors across platforms
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('no route to host') ||
        lower.contains('xmlhttprequest')) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    }

    // If it contains technical traces or stack details, mask it
    if (_technicalRegex.hasMatch(raw) ||
        raw.startsWith('Exception:') ||
        raw.startsWith('Error:')) {
      return fallback;
    }

    // If it's a reasonably short and readable string without code artifacts, show it
    final cleaned = raw.replaceAll(RegExp(r'^Exception:\s*'), '').trim();
    if (cleaned.isNotEmpty && cleaned.length <= 160 && !_technicalRegex.hasMatch(cleaned)) {
      return cleaned;
    }

    return fallback;
  }
}
