import 'package:flutter_test/flutter_test.dart';
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
  });
}
