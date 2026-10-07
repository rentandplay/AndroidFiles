import 'package:flutter/foundation.dart';

/// Checks the customer's handoff QR after the assigned unit was prepared at the shop.
class ReleaseVerification extends ChangeNotifier {
  ReleaseVerification({required this.rentalId, required this.request});
  final String rentalId;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) request;
  int step = 0, _revision = 0;
  bool bookingVerified = false, inventoryVerified = false, busy = false;
  bool manual = false, _disposed = false;
  String transactionCode = '',
      inventoryCode = '',
      manualReason = '',
      error = '';
  Map<String, dynamic>? item;

  void updateTransaction(String value) {
    if (value == transactionCode) return;
    transactionCode = value;
    _invalidate(booking: true);
  }

  void updateInventory(String value) {
    if (value == inventoryCode) return;
    inventoryCode = value;
    _invalidate(booking: false);
  }

  void updateManual(bool value) {
    if (value == manual) return;
    manual = value;
    _invalidate(booking: true);
  }

  void updateReason(String value) {
    if (value == manualReason) return;
    manualReason = value;
    if (manual) _invalidate(booking: true);
  }

  void _invalidate({required bool booking}) {
    _revision++;
    busy = false;
    error = '';
    inventoryVerified = false;
    item = null;
    if (booking) {
      bookingVerified = false;
      step = 0;
    } else if (step > 1) {
      step = 1;
    }
    _emit();
  }

  void back() {
    if (!busy && step > 0) {
      step = 0;
      error = '';
      _emit();
    }
  }

  Future<void> verify() async {
    if (busy || step > 0) return;
    if (transactionCode.trim().isEmpty) {
      error = 'Scan or enter the customer rental QR.';
      _emit();
      return;
    }
    if (manual && manualReason.trim().isEmpty) {
      error = 'Explain why you are using the printed codes.';
      _emit();
      return;
    }
    final revision = ++_revision;
    busy = true;
    error = '';
    _emit();
    try {
      final result = await request({
        'transactionCode': transactionCode.trim(),
        if (manual) 'manualReason': manualReason.trim(),
      });
      if (_disposed || revision != _revision) return;
      final rental = result['rental'];
      if (rental is! Map ||
          rental['id'] != rentalId ||
          result['booking_verified'] != true ||
          result['delivery_prepared'] != true) {
        throw StateError('The rental QR is not ready for delivery handoff.');
      }
      bookingVerified = true;
      inventoryVerified = true;
      item = result['item'] is Map
          ? Map<String, dynamic>.from(result['item'])
          : null;
      step = 2;
    } catch (exception) {
      if (_disposed || revision != _revision) return;
      error = '$exception';
    } finally {
      if (!_disposed && revision == _revision) {
        busy = false;
        _emit();
      }
    }
  }

  Map<String, dynamic> get releaseCodes {
    if (step != 2 || busy || !bookingVerified || !inventoryVerified) {
      throw StateError('Verify the customer rental QR before handoff.');
    }
    return {
      'transactionCode': transactionCode.trim(),
      if (manual) 'manualReason': manualReason.trim(),
    };
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
