import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rental_model.dart';

class CachedRentalListSnapshot {
  const CachedRentalListSnapshot({
    required this.rentals,
    required this.savedAt,
  });

  final List<RentalModel> rentals;
  final DateTime savedAt;
}

/// Best-effort local cache scoped per customer account so active rental details
/// and handoff QR passes remain viewable inside resort Wi-Fi/cellular dead spots.
class RentalOfflineCache {
  const RentalOfflineCache._();

  static String _listKey(String scope) => 'rental_offline_list:${scope.trim()}';
  static String _ticketKey(String scope, String rentalId) =>
      'rental_offline_ticket:${scope.trim()}:${rentalId.trim()}';

  static dynamic _toJsonSafe(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is List) {
      return value.map(_toJsonSafe).toList();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _toJsonSafe(entry.value),
      };
    }
    return value.toString();
  }

  static Future<void> saveRentals(
    String? scope,
    List<RentalModel> rentals, {
    DateTime? now,
  }) async {
    final cleanScope = scope?.trim() ?? '';
    if (cleanScope.isEmpty) return;
    try {
      final prefs = SharedPreferencesAsync();
      final payload = jsonEncode({
        'savedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'rentals': rentals.map((r) => _toJsonSafe(r.toMap())).toList(),
      });
      await prefs.setString(_listKey(cleanScope), payload);
    } catch (_) {
      // Best-effort offline cache; ignore when platform storage is unavailable.
    }
  }

  static Future<CachedRentalListSnapshot?> loadRentals(String? scope) async {
    final cleanScope = scope?.trim() ?? '';
    if (cleanScope.isEmpty) return null;
    try {
      final prefs = SharedPreferencesAsync();
      final raw = await prefs.getString(_listKey(cleanScope));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt =
          DateTime.tryParse(decoded['savedAt']?.toString() ?? '')?.toLocal() ??
              DateTime.now();
      final list = decoded['rentals'];
      if (list is! List) return null;
      final rentals = list.whereType<Map>().map((entry) {
        final map = Map<String, dynamic>.from(entry);
        return RentalModel.fromMap(
          map,
          id: (map['id'] ?? map['rentalId'])?.toString(),
        );
      }).toList();
      return CachedRentalListSnapshot(rentals: rentals, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTicket(
    String? scope,
    String rentalId,
    Map<String, dynamic> ticket, {
    DateTime? now,
  }) async {
    final cleanScope = scope?.trim() ?? '';
    final cleanRentalId = rentalId.trim();
    if (cleanScope.isEmpty || cleanRentalId.isEmpty) return;
    try {
      final prefs = SharedPreferencesAsync();
      final sanitized = Map<String, dynamic>.from(_toJsonSafe(ticket) as Map)
        ..remove('rolling_pin')
        ..remove('offline_cached')
        ..remove('cached_at');
      final payload = jsonEncode({
        'savedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'ticket': sanitized,
      });
      await prefs.setString(_ticketKey(cleanScope, cleanRentalId), payload);
    } catch (_) {
      // Best-effort offline cache; ignore when platform storage is unavailable.
    }
  }

  static Future<Map<String, dynamic>?> loadTicket(
    String? scope,
    String rentalId,
  ) async {
    final cleanScope = scope?.trim() ?? '';
    final cleanRentalId = rentalId.trim();
    if (cleanScope.isEmpty || cleanRentalId.isEmpty) return null;
    try {
      final prefs = SharedPreferencesAsync();
      final raw = await prefs.getString(_ticketKey(cleanScope, cleanRentalId));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final ticket = decoded['ticket'];
      if (ticket is! Map) return null;
      return {
        ...Map<String, dynamic>.from(ticket),
        'offline_cached': true,
        'cached_at': decoded['savedAt']?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static String _resortKey(String scope) =>
      'rental_preferred_resort:${scope.trim()}';

  static Future<void> savePreferredResort(
    String? scope,
    String resort, {
    String? customResort,
  }) async {
    final cleanScope = scope?.trim() ?? '';
    final cleanResort = resort.trim();
    if (cleanScope.isEmpty || cleanResort.isEmpty) return;
    try {
      final prefs = SharedPreferencesAsync();
      final payload = jsonEncode({
        'resort': cleanResort,
        if (customResort != null && customResort.trim().isNotEmpty)
          'customResort': customResort.trim(),
      });
      await prefs.setString(_resortKey(cleanScope), payload);
    } catch (_) {}
  }

  static Future<Map<String, String>?> loadPreferredResort(String? scope) async {
    final cleanScope = scope?.trim() ?? '';
    if (cleanScope.isEmpty) return null;
    try {
      final prefs = SharedPreferencesAsync();
      final raw = await prefs.getString(_resortKey(cleanScope));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final resort = decoded['resort']?.toString().trim() ?? '';
      if (resort.isEmpty) return null;
      final custom = decoded['customResort']?.toString().trim() ?? '';
      return {
        'resort': resort,
        if (custom.isNotEmpty) 'customResort': custom,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAll({String? scope}) async {
    try {
      final prefs = SharedPreferencesAsync();
      final cleanScope = scope?.trim() ?? '';
      if (cleanScope.isNotEmpty) {
        await prefs.remove(_listKey(cleanScope));
        await prefs.remove(_resortKey(cleanScope));
      } else {
        await prefs.clear();
      }
    } catch (_) {}
  }
}
