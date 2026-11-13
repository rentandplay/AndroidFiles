import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/services/rental_receipt.dart';
import 'package:rent_and_play_app/models/rental_model.dart';

void main() {
  test(
      'saved fulfillment distinguishes Lakewoods shop handover from resort delivery and survives copying',
      () {
    final shop = RentalModel.fromMap({
      'id': 'shop',
      'status': 'APPROVED',
      'fulfillment_mode': 'SHOP_HANDOVER',
      'delivery_status': 'PREPARED',
      'delivery_location': 'Rent & Play · Lakewoods, Los Baños'
    });
    expect(shop.isRentAndPlayPickup, isTrue);
    expect(shop.customerHandoffLocation, contains('Lakewoods Subdivision'));
    expect(shop.statusLabel, 'Ready for shop handover');
    final copied =
        RentalModel.fromMap(shop.copyWith(itemName: 'Updated').toMap());
    expect(copied.fulfillmentMode, 'SHOP_HANDOVER');
    final delivery = RentalModel.fromMap({
      'id': 'delivery',
      'status': 'APPROVED',
      'fulfillment_mode': 'DELIVERY',
      'delivery_status': 'PREPARED',
      'delivery_location': 'ASRI Hotspring Resort'
    });
    expect(delivery.isRentAndPlayPickup, isFalse);
    expect(delivery.customerHandoffLocation, 'ASRI Hotspring Resort');
    expect(delivery.statusLabel, 'Ready for delivery');
    expect(
        RentalModel.fromMap({'delivery_location': 'ASRI Hotspring Resort'})
            .isRentAndPlayPickup,
        isFalse);
    expect(
        RentalModel.fromMap({'fulfillment_mode': 'DELIVERY'})
            .customerHandoffLocation,
        'Delivery location not recorded');
  });
  test('approved booking is cancellable and awaits pickup', () {
    final rental = RentalModel.fromMap({
      'id': 'booking',
      'status': 'APPROVED',
      'rental_code': 'R-1',
      'item_image_url': 'https://example.test/volleyball.png',
      'created_at': '2026-10-06T02:00:00Z',
      'hold_expires_at': '2026-10-06T02:30:00Z',
    });
    expect(rental.isAwaitingPickup, isTrue);
    expect(rental.canCancel, isTrue);
    expect(rental.isActive, isFalse);
    expect(rental.itemImageUrl, 'https://example.test/volleyball.png');
    expect(rental.holdExpiresAt!.toUtc(), DateTime.utc(2026, 10, 6, 2, 30));
  });
  test(
      'physical receipt and legacy Manila timestamps survive model copies and storage',
      () {
    final rental = RentalModel.fromMap({
      'id': 'rental',
      'status': 'RETURN_PENDING_INSPECTION',
      'received_at': '2026-10-06T06:00:00Z',
      'confirmed_return_at': '2026-10-06T07:00:00Z',
      'start_at': '2026-10-06 10:00:00.000',
      'balance_due': 20,
      'refund_due': 100,
      'payment_status': 'REFUND_PENDING',
      'return_condition': {'condition': 'DAMAGED', 'notes': 'Missing part'},
    });
    expect(rental.isAwaitingInspection, isTrue);
    expect(rental.isActive, isFalse);
    expect(rental.isOpen, isTrue);
    expect(rental.returnedDate!.toUtc(), DateTime.utc(2026, 10, 6, 6));
    expect(rental.startDate.toUtc(), DateTime.utc(2026, 10, 6, 2));
    expect(rental.returnCondition, 'DAMAGED');
    final copied =
        RentalModel.fromMap(rental.copyWith(itemName: 'Updated').toMap());
    expect(copied.receivedAt, rental.receivedAt);
    expect(copied.balanceDue, 20);
    expect(copied.refundDue, 100);
    expect(copied.paymentStatus, 'REFUND_PENDING');

    final terminalPending = RentalModel.fromMap({
      'id': 'rental-esp',
      'status': 'RETURN_PENDING_INSPECTION',
      'latest_return_request_status': 'PENDING',
      'latest_terminal_request_status': 'PENDING',
    });
    expect(terminalPending.isReturnAwaitingTerminalConfirmation, isTrue);
    expect(
        RentalModel.fromMap(terminalPending.copyWith(itemName: 'Board').toMap())
            .isReturnAwaitingTerminalConfirmation,
        isTrue);
  });

  test(
      'toReceiptMap preserves fee breakdown, inspection details, and generates PDF receipt bytes',
      () async {
    final completed = RentalModel.fromMap({
      'id': 'rental-receipt-1',
      'rental_code': 'R-0331',
      'item_id': 'item-1',
      'item_code': 'VB-01',
      'item_name': 'Volleyball',
      'customer_name': 'Sai',
      'customer_phone': '09123456789',
      'status': 'COMPLETED',
      'payment_method': 'Cash',
      'rental_fee': 250,
      'rental_paid_amount': 250,
      'overtime_fee': 50,
      'penalty_amount': 75,
      'penalty_reason': 'Worn net',
      'final_rental_charges': 375,
      'balance_due': 125,
      'refund_due': 0,
      'confirmed_rental_at': '2026-10-06T02:00:00Z',
      'due_at': '2026-10-06T05:00:00Z',
      'received_at': '2026-10-06T06:00:00Z',
      'confirmed_return_at': '2026-10-06T06:05:00Z',
      'return_condition': {
        'condition': 'FAIR',
        'notes': 'Slightly scuffed',
        'result': 'AVAILABLE',
        'inspected_by_name': 'Admin Staff',
      },
      'fee_breakdown': {
        'rental_fee': 250,
        'billed_minutes': 180,
        'grace_minutes': 10,
        'overtime_rate': 50,
        'overtime_unit_minutes': 60,
        'overtime_units': 1,
        'overtime_fee': 50,
        'penalty_amount': 75,
        'penalty_reason': 'Worn net',
        'final_rental_charges': 375,
      },
    });

    final receiptMap = completed.toReceiptMap();
    final fee = receiptMap['fee_breakdown'] as Map<String, dynamic>;
    final cond = receiptMap['return_condition'] as Map<String, dynamic>;

    expect(receiptMap['rental_code'], 'R-0331');
    expect(receiptMap['item_code'], 'VB-01');
    expect(receiptMap['customer_phone'], '09123456789');
    expect(receiptMap['rental_paid_amount'], 250.0);
    expect(receiptMap['balance_due'], 125.0);
    expect(fee['overtime_fee'], 50.0);
    expect(fee['penalty_amount'], 75.0);
    expect(fee['penalty_reason'], 'Worn net');
    expect(fee['final_rental_charges'], 375.0);
    expect(fee['billed_minutes'], 180);
    expect(fee['grace_minutes'], 10);
    expect(cond['condition'], 'FAIR');
    expect(cond['notes'], 'Slightly scuffed');
    expect(cond['result'], 'AVAILABLE');

    final pdfBytes = await buildRentalReceipt(receiptMap);
    expect(pdfBytes.length, greaterThan(100));
    expect(String.fromCharCodes(pdfBytes.take(4)), '%PDF');
  });

  test('extension_request, extension_history, and total_extended_minutes roundtrip via toMap and copyWith', () {
    final model = RentalModel.fromMap({
      'id': 'r-ext',
      'status': 'ACTIVE',
      'due_at': '2026-11-14T11:31:00Z',
      'total_extended_minutes': 180,
      'extension_request': {
        'status': 'PENDING',
        'additional_minutes': 180,
        'additional_fee': 500,
        'requested_due_at': '2026-11-14T11:31:00Z',
        'quote': {'billed_minutes': 180},
      },
      'extension_history': [
        {
          'status': 'APPROVED',
          'additional_minutes': 180,
          'requested_due_at': '2026-11-14T11:31:00Z',
          'reviewed_at': '2026-11-14T08:31:00Z',
          'quote': {'billed_minutes': 180},
        },
      ],
    });
    expect(model.hasPendingExtensionRequest, isTrue);
    expect(model.requestedExtensionMinutes, 180);
    expect(model.requestedExtensionFee, 500);
    expect(model.effectiveTotalExtendedMinutes, 180);
    expect(model.extensionCount, 1);
    expect(model.requestedExtensionDueDate!.toUtc(), DateTime.utc(2026, 11, 14, 11, 31));

    final restored = RentalModel.fromMap(model.copyWith(rateFee: 5200).toMap());
    expect(restored.hasPendingExtensionRequest, isTrue);
    expect(restored.totalExtendedMinutes, 180);
    expect(restored.extensionHistory.length, 1);
    expect(restored.rateFee, 5200);
  });
}
