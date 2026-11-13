import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../models/rental_model.dart';
import '../services/rental_receipt.dart';
import '../theme/app_theme.dart';
import 'rental_ui.dart';

typedef ReceiptPdfAction = Future<void> Function(
    RentalModel rental, Map<String, dynamic> receiptMap);

/// Itemized customer receipt shown during return receipt check and completion,
/// as well as inside rental history details, with PDF print/save and share actions.
class RentalReceiptCard extends StatefulWidget {
  const RentalReceiptCard({
    super.key,
    required this.rental,
    this.isPreview = false,
    this.onPrintOrSavePdf,
    this.onSharePdf,
  });

  final RentalModel rental;
  final bool isPreview;
  final ReceiptPdfAction? onPrintOrSavePdf;
  final ReceiptPdfAction? onSharePdf;

  @override
  State<RentalReceiptCard> createState() => _RentalReceiptCardState();
}

class _RentalReceiptCardState extends State<RentalReceiptCard> {
  bool _printingPdf = false;
  bool _sharingPdf = false;

  String _formatDate(DateTime? value) => value == null ||
          value.millisecondsSinceEpoch <= 0
      ? 'Not recorded'
      : DateFormat('MMM d, yyyy · h:mm a').format(value.toLocal());

  String _formatDuration(int? minutes) {
    if (minutes == null || minutes <= 0) return 'Not recorded';
    if (minutes < 60) return '$minutes min';
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    final remMins = minutes % 60;
    if (days > 0) {
      return '$days d ${hours > 0 ? '$hours hr ' : ''}${remMins > 0 ? '$remMins min' : ''}'
          .trim();
    }
    return remMins > 0 ? '$hours hr $remMins min' : '$hours hr';
  }

  String _humanLabel(String raw, [String fallback = 'Not recorded']) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    return trimmed
        .toLowerCase()
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  double? _computedOvertimeFee(RentalModel rental) {
    if (rental.overtimeFee != null) return rental.overtimeFee;
    final received = rental.receivedAt;
    if (received == null || rental.dueDate.millisecondsSinceEpoch <= 0) {
      return null;
    }
    final elapsedLate = received.difference(rental.dueDate).inMinutes;
    final grace = rental.graceMinutes ?? 0;
    final billableLate = (elapsedLate - grace).clamp(0, 1 << 30);
    if (billableLate == 0) return 0;
    final unitMinutes =
        rental.overtimeUnitMinutes > 0 ? rental.overtimeUnitMinutes : 60;
    final units = (billableLate + unitMinutes - 1) ~/ unitMinutes;
    return units * rental.overtimeRate;
  }

  Map<String, dynamic> _resolvedReceiptMap() {
    final rental = widget.rental;
    final base = rental.toReceiptMap();
    final overtime = _computedOvertimeFee(rental);
    final penalty = rental.penaltyAmount ?? 0;
    final fee = Map<String, dynamic>.from(
        base['fee_breakdown'] as Map? ?? const <String, dynamic>{});
    if (fee['overtime_fee'] == null && overtime != null) {
      fee['overtime_fee'] = overtime;
    }
    if (fee['penalty_amount'] == null) {
      fee['penalty_amount'] = penalty;
    }
    if (fee['final_rental_charges'] == null && overtime != null) {
      fee['final_rental_charges'] = rental.rateFee + overtime + penalty;
    }
    base['fee_breakdown'] = fee;
    return base;
  }

  String _pdfFilename(RentalModel rental) {
    final ref = rental.rentalCode.trim().isNotEmpty
        ? rental.rentalCode.trim()
        : rental.rentalId;
    final safeRef = ref.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return 'Rental-${safeRef.isEmpty ? 'receipt' : safeRef}.pdf';
  }

  Future<void> _handlePrintOrSave() async {
    if (_printingPdf || _sharingPdf) return;
    setState(() => _printingPdf = true);
    try {
      final receiptMap = _resolvedReceiptMap();
      if (widget.onPrintOrSavePdf != null) {
        await widget.onPrintOrSavePdf!(widget.rental, receiptMap);
      } else {
        await Printing.layoutPdf(
          name: _pdfFilename(widget.rental),
          onLayout: (_) => buildRentalReceipt(receiptMap),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open receipt PDF: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _printingPdf = false);
    }
  }

  Future<void> _handleSharePdf() async {
    if (_printingPdf || _sharingPdf) return;
    setState(() => _sharingPdf = true);
    try {
      final receiptMap = _resolvedReceiptMap();
      if (widget.onSharePdf != null) {
        await widget.onSharePdf!(widget.rental, receiptMap);
      } else {
        final Uint8List bytes = await buildRentalReceipt(receiptMap);
        final ref = widget.rental.rentalCode.trim().isNotEmpty
            ? widget.rental.rentalCode.trim()
            : widget.rental.rentalId;
        await Printing.sharePdf(
          bytes: bytes,
          filename: _pdfFilename(widget.rental),
          subject: 'Rent & Play Receipt · $ref',
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share receipt PDF: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final rental = widget.rental;
    final overtime = _computedOvertimeFee(rental);
    final penalty = rental.penaltyAmount ?? 0;
    final computedTotal = rental.finalRentalCharges ??
        (overtime != null ? rental.rateFee + overtime + penalty : null);
    final effectiveBalance = computedTotal != null &&
            rental.rentalPaidAmount != null
        ? (computedTotal - rental.rentalPaidAmount!).clamp(0.0, double.infinity)
        : rental.balanceDue;
    final unitSummary = rental.itemCode.trim().isEmpty
        ? rental.itemName
        : '${rental.itemName} (${rental.itemCode.trim()})';
    final startedAt = rental.confirmedRentalAt ??
        (rental.startDate.millisecondsSinceEpoch > 0 ? rental.startDate : null);

    return RentalSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.brandOrange.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 20,
                  color: AppTheme.brandOrange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isPreview ? 'Receipt preview' : 'Official receipt',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      'Rent & Play · Lakewoods Subdivision',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  rental.displayReference,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF141E2E).withValues(alpha: 0.72)
                  : const Color(0xFFFDFBF8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outline.withValues(alpha: isDark ? 0.28 : 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RentalValueRow('Equipment', unitSummary),
                RentalValueRow('Customer', rental.customerName),
                RentalValueRow(
                  'Handover',
                  rental.isRentAndPlayPickup
                      ? 'At shop'
                      : rental.customerHandoffLocation,
                ),
                if (startedAt != null)
                  RentalValueRow('Rental started', _formatDate(startedAt)),
                if (rental.dueDate.millisecondsSinceEpoch > 0)
                  RentalValueRow('Return due', _formatDate(rental.dueDate)),
                if (rental.receivedAt != null)
                  RentalValueRow(
                      'Received by admin', _formatDate(rental.receivedAt)),
                if (rental.confirmedReturnAt != null)
                  RentalValueRow('Return confirmed',
                      _formatDate(rental.confirmedReturnAt)),
                if (rental.billedMinutes != null)
                  RentalValueRow(
                      'Billed duration', _formatDuration(rental.billedMinutes)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF141E2E).withValues(alpha: 0.72)
                  : const Color(0xFFFDFBF8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outline.withValues(alpha: isDark ? 0.28 : 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'INSPECTION & CHARGES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                RentalValueRow(
                  'Returned condition',
                  _humanLabel(rental.returnCondition, 'Good'),
                ),
                if (rental.returnResult.trim().isNotEmpty)
                  RentalValueRow(
                    'Inspection outcome',
                    _humanLabel(rental.returnResult),
                  ),
                if (rental.conditionNotes.trim().isNotEmpty)
                  RentalValueRow(
                    'Inspector notes',
                    rental.conditionNotes.trim(),
                  ),
                const Divider(height: 20),
                RentalValueRow('Rental fee', rentalMoney(rental.rateFee)),
                RentalValueRow(
                  'Late charges',
                  overtime != null ? rentalMoney(overtime) : '₱0.00',
                ),
                RentalValueRow(
                  'Damage / missing penalty',
                  rentalMoney(penalty),
                ),
                if (rental.penaltyReason.trim().isNotEmpty)
                  RentalValueRow(
                    'Penalty reason',
                    rental.penaltyReason.trim(),
                  ),
                const Divider(height: 20),
                RentalValueRow(
                  'Total charges',
                  computedTotal != null
                      ? rentalMoney(computedTotal)
                      : rentalMoney(rental.rateFee),
                  emphasis: true,
                ),
                RentalValueRow(
                  'Amount paid (${rental.paymentMethod})',
                  rental.rentalPaidAmount != null
                      ? rentalMoney(rental.rentalPaidAmount!)
                      : 'Not recorded',
                ),
                if (effectiveBalance > 0)
                  RentalValueRow(
                    'Balance due',
                    rentalMoney(effectiveBalance),
                    emphasis: true,
                  )
                else if (rental.refundDue > 0)
                  RentalValueRow(
                    'Refund due',
                    rentalMoney(rental.refundDue),
                    emphasis: true,
                  )
                else if (computedTotal != null)
                  const RentalValueRow('Settlement', 'Paid / Settled'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('receipt-print-save-pdf'),
                  onPressed: _printingPdf || _sharingPdf
                      ? null
                      : _handlePrintOrSave,
                  icon: _printingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 19),
                  label: Text(
                      _printingPdf ? 'Opening PDF…' : 'Print / Save PDF'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('receipt-share-pdf'),
                  onPressed:
                      _printingPdf || _sharingPdf ? null : _handleSharePdf,
                  icon: _sharingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(_sharingPdf ? 'Preparing…' : 'Save / Share'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
