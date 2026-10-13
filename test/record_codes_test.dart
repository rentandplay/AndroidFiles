import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/models/rental_model.dart';
import 'package:rent_and_play_app/utils/record_codes.dart';

void main() {
  test(
      'mobile uses the shared saved reference and keeps internal IDs for requests',
      () {
    final rental = RentalModel.fromMap({
      'id': 'booking_long_internal_record_id',
      'rental_code': 'R-0001',
      'terminal_id': 'terminal_long_internal_id',
      'terminal_code': 'TERM-001',
      'status': 'APPROVED',
    });
    expect(rental.rentalId, 'booking_long_internal_record_id');
    expect(rental.displayReference, 'R-0001');
    expect(rental.terminalReference, 'TERM-001');
    expect(rental.copyWith(status: 'ACTIVE').displayReference, 'R-0001');
    expect(
        recordReference({'request_code': 'V-0002'}, 'verification'), 'V-0002');
  });

  test('missing references never become truncated internal IDs', () {
    expect(recordReference({'id': 'booking_long_record'}), 'Not assigned');
    expect(RentalModel.fromMap({'id': 'x'}).displayReference, 'Not assigned');
  });

  test(
      'QR tickets must match the exact rental and contain a saved reference and scan value',
      () {
    final ticket = {
      'rental_id': 'actual-rental-id',
      'rental_code': 'R-0001',
      'value': 'rp-rental-original-scan-token',
    };
    expect(validateRentalTicket(ticket, 'actual-rental-id'), same(ticket));
    expect(() => validateRentalTicket(ticket, 'another-rental-id'),
        throwsStateError);
    expect(
        () =>
            validateRentalTicket({...ticket, 'value': ''}, 'actual-rental-id'),
        throwsStateError);
  });
}
