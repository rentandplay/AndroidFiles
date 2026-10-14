import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import '../utils/record_codes.dart';

Future<Uint8List> buildRentalReceipt(Map<String, dynamic> row) async {
  final document = pw.Document();
  final fee = row['fee_breakdown'] is Map
      ? Map<String, dynamic>.from(row['fee_breakdown'])
      : <String, dynamic>{};
  String money(dynamic value) => value is num && value.isFinite
      ? 'PHP ${value.toStringAsFixed(2)}'
      : 'Not recorded';
  String date(dynamic value) {
    if (value == null || value.toString().isEmpty) return 'Not recorded';
    final raw = value.toString();
    final parsed = DateTime.tryParse(RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(raw)
        ? raw
        : '${raw.replaceFirst(' ', 'T')}+08:00');
    return parsed == null
        ? 'Not recorded'
        : DateFormat('MMM d, yyyy h:mm a')
            .format(parsed.toUtc().add(const Duration(hours: 8)));
  }

  final fields = <List<String>>[
    ['Customer', row['customer_name']?.toString() ?? 'Not recorded'],
    ['Contact number', row['customer_phone']?.toString() ?? 'Not recorded'],
    [
      'Equipment / unit',
      '${row['item_name'] ?? ''} / ${row['item_code'] ?? ''}'
    ],
    [
      'Handover method',
      row['fulfillment_mode'] == 'SHOP_HANDOVER'
          ? 'At Rent & Play establishment'
          : 'Resort delivery'
    ],
    ['Location', row['delivery_location']?.toString() ?? 'Not recorded'],
    ['Rental started', date(row['confirmed_rental_at'])],
    ['Return due', date(row['due_at'])],
    ['Billed duration', '${fee['billed_minutes'] ?? 'Not recorded'} minutes'],
    ['Rental fee', money(row['rental_fee'])],
    ['Payment received', money(row['rental_paid_amount'])],
    [
      'Late fee',
      '${money(fee['overtime_rate'])} per started ${fee['overtime_unit_minutes'] ?? 60} minutes'
    ],
    if (fee['final_rental_charges'] != null)
      ['Final rental charges', money(fee['final_rental_charges'])],
    ['Outstanding balance', money(row['balance_due'])],
    ['Physical return received', date(row['received_at'])],
    [
      'Grace period',
      fee['grace_minutes'] == null
          ? 'Not recorded'
          : '${fee['grace_minutes']} minutes'
    ],
    ['Rental status', row['status']?.toString() ?? 'Not recorded'],
  ];
  document.addPage(pw.MultiPage(
      build: (_) => [
            pw.Text('Rent & Play',
                style:
                    pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.Text('Lakewoods Subdivision, Los Banos, Laguna'),
            pw.SizedBox(height: 16),
            pw.Text('Rental receipt: ${recordReference(row)}',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            for (final field in fields)
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  child: pw.Row(children: [
                    pw.Expanded(child: pw.Text(field[0])),
                    pw.Expanded(
                        child: pw.Text(field[1], textAlign: pw.TextAlign.right))
                  ])),
            pw.SizedBox(height: 16),
            pw.Text(
                'Keep this rental reference for follow-ups. The timer starts at confirmed physical handover and stops when staff physically receives the equipment. Staff inspect the unit and accessories before completing the return. Late fees and assessed damage or missing parts may affect the final balance.'),
          ]));
  return document.save();
}
