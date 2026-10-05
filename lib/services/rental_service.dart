import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../models/item_model.dart';

class RentalService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new Rental Transaction with status PENDING_HARDWARE_CONFIRMATION
  Future<TransactionModel?> createRentalTransaction({
    required ItemModel item,
    required String customerId,
    required String customerName,
    required String terminalId,
    required double rateFee,
    required double deposit,
  }) async {
    try {
      final docRef = _firestore.collection('rentals').doc();
      final now = DateTime.now();

      // ESP32 HARDWARE TRIGGER 1:
      // App initializes a transaction document with status PENDING_HARDWARE_CONFIRMATION.
      // The ESP32 terminal reads this Firestore state via Realtime Database or Firestore listener
      // to await physical cabinet release.
      final transaction = TransactionModel(
        transactionId: docRef.id,
        itemId: item.id,
        itemName: item.name,
        customerId: customerId,
        customerName: customerName,
        terminalId: terminalId,
        hardwareConfirmed: false,
        status: 'PENDING_HARDWARE_CONFIRMATION',
        rateFee: rateFee,
        deposit: deposit,
        createdAt: now,
        updatedAt: now,
      );

      await docRef.set(transaction.toMap());
      notifyListeners();
      return transaction;
    } catch (e) {
      debugPrint('Firestore Write Failure - Create Rental Error: $e');
      rethrow;
    }
  }

  // Stream real-time Firestore transaction document snapshots
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamTransaction(String transactionId) {
    return _firestore.collection('rentals').doc(transactionId).snapshots();
  }

  // Initiate Return Flow - Status: PENDING_RETURN_VERIFICATION
  Future<void> initiateReturnTransaction(String transactionId) async {
    try {
      // ESP32 HARDWARE TRIGGER 2:
      // Status becomes PENDING_RETURN_VERIFICATION.
      // ESP32 cabinet prepares solenoid lock for physical item return and inspection.
      await _firestore.collection('rentals').doc(transactionId).update({
        'status': 'PENDING_RETURN_VERIFICATION',
        'hardwareConfirmed': false,
        'updatedAt': Timestamp.now(),
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Firestore Write Failure - Return Request Error: $e');
      rethrow;
    }
  }

  // Confirm Hardware Transaction (Triggered by ESP32 Physical Button or Operator Overwrite)
  Future<void> confirmHardwareTransaction({
    required String transactionId,
    required String itemId,
    required bool isReturn,
  }) async {
    try {
      final finalStatus = isReturn ? 'COMPLETED' : 'RENTED';
      final itemStatus = isReturn ? 'available' : 'rented';

      // ESP32 HARDWARE TRIGGER 3:
      // Physical button press or operator override triggers status update to RENTED or COMPLETED.
      // Lock solenoids lock/unlock and hardware_confirmed is flagged as true.
      await _firestore.collection('rentals').doc(transactionId).update({
        'status': finalStatus,
        'hardwareConfirmed': true,
        'updatedAt': Timestamp.now(),
      });

      // Synchronize Item stock status
      await _firestore.collection('items').doc(itemId).set({
        'status': itemStatus,
      }, SetOptions(merge: true));

      notifyListeners();
    } catch (e) {
      debugPrint('Firestore Hardware Confirmation Failure: $e');
      rethrow;
    }
  }

  // Cancel Transaction on Timeout or User Rejection
  Future<void> cancelTransaction(String transactionId, String reason) async {
    try {
      // ESP32 HARDWARE TRIGGER 4:
      // Transaction cancelled or 60s timeout exceeded.
      // Lock state resets and transaction is aborted in Firestore.
      await _firestore.collection('rentals').doc(transactionId).update({
        'status': 'CANCELLED',
        'cancelReason': reason,
        'updatedAt': Timestamp.now(),
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Firestore Cancel Transaction Failure: $e');
    }
  }
}
