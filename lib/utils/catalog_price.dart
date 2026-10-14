import 'package:intl/intl.dart';

import '../models/item_model.dart';

/// A short, configured package price; the full rate sheet remains in details.
String catalogPriceLabel(ItemModel item) {
  final options = item.rateOptions.where((option) {
    final amount = option['amount'];
    return amount is num &&
        amount.isFinite &&
        amount >= 0 &&
        option['kind'] != 'WHOLE_STAY' &&
        option['label'] is String &&
        (option['label'] as String).trim().isNotEmpty;
  }).toList()
    ..sort((a, b) => (a['amount'] as num).compareTo(b['amount'] as num));
  if (options.isNotEmpty) {
    final amount =
        NumberFormat('#,##0.##', 'en').format(options.first['amount']);
    return '${options.length > 1 ? 'From ' : ''}₱$amount / ${options.first['label']}';
  }
  final text = item.rateText.trim();
  if (text.isEmpty) return 'View rental rates';
  // Split package separators without splitting thousands separators in money.
  final packages =
      text.split(RegExp(r'\s*·\s*|\s*,\s*(?=₱|Rent\b|Buy\b|Sale\b)'));
  final first = packages.first
      .replaceFirst(RegExp(r'^Rent\s+', caseSensitive: false), '');
  return '${packages.length > 1 ? 'From ' : ''}$first';
}
