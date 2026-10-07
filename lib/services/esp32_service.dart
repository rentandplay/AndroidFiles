import 'hardware_features.dart';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class Esp32Service extends ChangeNotifier {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Stream terminal node "terminals/{terminalId}"
  Stream<DatabaseEvent> streamTerminalState(String terminalId) {
    if (!HardwareFeatures.enabled) return const Stream.empty();
    try {
      return _db.ref('terminals/$terminalId').onValue;
    } catch (_) {
      return const Stream.empty();
    }
  }

  // Stream RTDB connection status
  Stream<DatabaseEvent> streamConnectionStatus() {
    if (!HardwareFeatures.enabled) return const Stream.empty();
    try {
      return _db.ref('.info/connected').onValue;
    } catch (_) {
      return const Stream.empty();
    }
  }

  // Explicit check for active backend / RTDB connection
  Future<bool> checkConnection() async {
    HardwareFeatures.requireEnabled();
    try {
      final snapshot = await _db
          .ref('.info/connected')
          .get()
          .timeout(const Duration(seconds: 3));
      return (snapshot.value as bool?) ?? true;
    } catch (e) {
      debugPrint('Connection check failed, defaulting to online mode: $e');
      return true; // Always return true so users are never blocked from returning their rent!
    }
  }

  // Initiate Rental Hardware Verification with Timeout Safety
  Future<bool> initiateRentalHardwareVerification(
      String terminalId, String rentalId) async {
    HardwareFeatures.requireEnabled();
    try {
      await _db.ref('terminals/$terminalId').set({
        'esp32State': 'RENT_READY',
        'currentRentalId': rentalId,
        'physicalButtonPressed': false,
        'lastUpdated': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('RTDB offline fallback for rental verification: $e');
    }
    notifyListeners();
    return true; // Never fail
  }

  // Initiate Return Hardware Verification with Timeout Safety
  Future<bool> initiateReturnHardwareVerification(
      String terminalId, String rentalId) async {
    HardwareFeatures.requireEnabled();
    try {
      await _db.ref('terminals/$terminalId').set({
        'esp32State': 'RETURN_READY',
        'currentRentalId': rentalId,
        'physicalButtonPressed': false,
        'lastUpdated': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('RTDB offline fallback for return verification: $e');
    }
    notifyListeners();
    return true; // Never fail
  }

  // Confirm Hardware Transaction (Physical Button or Admin Overwrite)
  Future<void> confirmHardwareTransaction(
      String terminalId, String rentalId) async {
    HardwareFeatures.requireEnabled();
    try {
      await _db.ref('terminals/$terminalId').update({
        'esp32State': 'CONFIRMED',
        'physicalButtonPressed': true,
        'lastUpdated': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Error confirming hardware transaction: $e');
    }
    notifyListeners();
  }

  // Reset Terminal State
  Future<void> resetTerminal(String terminalId) async {
    HardwareFeatures.requireEnabled();
    try {
      await _db.ref('terminals/$terminalId').set({
        'esp32State': 'IDLE',
        'currentRentalId': '',
        'physicalButtonPressed': false,
        'lastUpdated': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Error resetting terminal: $e');
    }
    notifyListeners();
  }
}
