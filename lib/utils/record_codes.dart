const _recordCodeFields = {
  'rental': 'rental_code',
  'equipment': 'item_code',
  'customer': 'customer_code',
  'verification': 'request_code',
  'maintenance': 'maintenance_code',
  'rate': 'rate_code',
  'category': 'category_code',
  'terminal': 'terminal_code',
  'account': 'account_code',
  'audit': 'audit_code',
  'condition': 'condition_code',
  'history': 'history_code',
};

/// Use the saved backend reference on every screen. Internal IDs stay intact
/// for API requests and QR verification; they are never shortened for display.
String recordReference(Map<dynamic, dynamic> row, [String type = 'rental']) {
  final value = row[_recordCodeFields[type]]?.toString().trim() ?? '';
  return value.isEmpty ? 'Not assigned' : value;
}

Map<String, dynamic> validateRentalTicket(
    Map<String, dynamic> ticket, String rentalId) {
  if (ticket['rental_id']?.toString() != rentalId) {
    throw StateError(
        'The rental QR belongs to a different rental. Refresh and try again.');
  }
  if (ticket['rental_code'] is! String ||
      (ticket['rental_code'] as String).trim().isEmpty ||
      ticket['value'] is! String ||
      (ticket['value'] as String).trim().isEmpty) {
    throw StateError('The rental QR is incomplete. Refresh and try again.');
  }
  return ticket;
}
