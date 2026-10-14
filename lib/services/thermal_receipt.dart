import '../utils/record_codes.dart';

String _clean(dynamic value) => (value?.toString() ?? '')
    .replaceAll(RegExp(r'[\s\x00-\x1f\x7f]+'), ' ')
    .trim();
String _money(dynamic value) => value is num && value.isFinite && value >= 0
    ? 'PHP ${value.toStringAsFixed(2)}'
    : 'Not recorded';
String _number(dynamic value) =>
    value is num && value % 1 == 0 ? value.toInt().toString() : _clean(value);
String _date(dynamic value) {
  final raw = _clean(value);
  if (raw.isEmpty) return 'Not recorded';
  final parsed = DateTime.tryParse(RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(raw)
      ? raw
      : '${raw.replaceFirst(' ', 'T')}+08:00');
  return parsed == null
      ? 'Not recorded'
      : parsed
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(0, 16)
          .replaceFirst('T', ' ');
}

/// Same saved fields and Manila dates as the web thermal receipt. No QR secrets.
List<Map<String, dynamic>> thermalReceiptLines(Map<String, dynamic> row) {
  final reference = recordReference(row);
  if (!RegExp(r'^R-[A-Z0-9]+$', caseSensitive: false).hasMatch(reference)) {
    throw StateError(
        'Refresh this rental to load its saved receipt reference.');
  }
  final fee = row['fee_breakdown'] is Map
      ? Map<String, dynamic>.from(row['fee_breakdown'])
      : <String, dynamic>{};
  final lines = <Map<String, dynamic>>[];
  void line(String text, [Map<String, dynamic> style = const {}]) =>
      lines.add({'text': _clean(text), ...style});
  void field(String label, dynamic value) =>
      line('$label: ${_clean(value).isEmpty ? 'Not recorded' : _clean(value)}');
  void divider() => lines.add({'text': '', 'separator': true});
  line('RENT & PLAY', {'bold': true, 'center': true, 'size': 26});
  line('Lakewoods Subdivision', {'center': true});
  line('Los Banos, Laguna', {'center': true});
  line('RENTAL RECEIPT', {'bold': true, 'center': true});
  line(reference, {'bold': true, 'center': true, 'size': 26});
  divider();
  field('Status', _clean(row['status']).replaceAll('_', ' '));
  field('Customer', row['customer_name']);
  field('Contact', row['customer_phone']);
  field('Equipment', row['item_name']);
  field('Unit', row['item_code']);
  field(
      'Handover',
      row['fulfillment_mode'] == 'SHOP_HANDOVER'
          ? 'At shop'
          : 'Resort delivery');
  field('Location', row['delivery_location']);
  field('Started', _date(row['confirmed_rental_at']));
  field('Due', _date(row['due_at']));
  field(
      'Duration',
      fee['billed_minutes'] is num && (fee['billed_minutes'] as num).isFinite
          ? '${_number(fee['billed_minutes'])} min'
          : null);
  divider();
  field('Rental fee', _money(row['rental_fee']));
  field('Payment method', row['payment_method']);
  field('Payment received', _money(row['rental_paid_amount']));
  if (fee['overtime_fee'] != null) {
    field('Late charges', _money(fee['overtime_fee']));
  }
  if (fee['penalty_amount'] != null) {
    field('Damage / missing', _money(fee['penalty_amount']));
  }
  if (fee['final_rental_charges'] != null) {
    field('Final total', _money(fee['final_rental_charges']));
  }
  field('Balance due', _money(row['balance_due']));
  if (row['refund_due'] != null &&
      ['COMPLETED', 'CANCELLED', 'REJECTED', 'EXPIRED']
          .contains(row['status'])) {
    field('Refund due', _money(row['refund_due']));
  }
  divider();
  field('Late rate',
      '${_money(fee['overtime_rate'])} / started ${_number(fee['overtime_unit_minutes'] ?? 60)} min');
  field(
      'Grace',
      fee['grace_minutes'] == null
          ? null
          : '${_number(fee['grace_minutes'])} min');
  if (_clean(row['received_at']).isNotEmpty) {
    field('Received', _date(row['received_at']));
  }
  line('Keep this rental reference.');
  line('Timer stops when staff receives the item.');
  line(
      'Return is subject to inspection. Damage or missing parts may affect final charges.');
  return lines;
}
