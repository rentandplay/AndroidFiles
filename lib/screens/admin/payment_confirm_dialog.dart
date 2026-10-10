import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/rental_model.dart';
import '../../models/item_model.dart';
import '../shared/equipment_qr_label_dialog.dart';

class PaymentConfirmDialog extends StatefulWidget {
  final RentalModel rental;

  const PaymentConfirmDialog({
    super.key,
    required this.rental,
  });

  static Future<bool?> show(BuildContext context, {required RentalModel rental}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => PaymentConfirmDialog(rental: rental),
    );
  }

  @override
  State<PaymentConfirmDialog> createState() => _PaymentConfirmDialogState();
}

class _PaymentConfirmDialogState extends State<PaymentConfirmDialog> {
  bool _isUpdating = false;

  Future<void> _confirmPayment() async {
    setState(() => _isUpdating = true);

    try {
      // Mark payment confirmed in Firestore
      await FirebaseFirestore.instance
          .collection('rentals')
          .doc(widget.rental.rentalId)
          .update({
        'paymentConfirmedByAdmin': true,
        'status': 'active',
      });

      // Update item status in Firestore to rented
      await FirebaseFirestore.instance
          .collection('items')
          .doc(widget.rental.itemId)
          .update({'status': 'rented'});

      if (!mounted) return;

      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed! ESP32 cabinet unlocked.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error confirming payment: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = widget.rental.rateFee;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.verified_user, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          const Text('Confirm Payment'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please verify customer payment details below before unlocking the ESP32 cabinet.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const Divider(height: 20),
            _buildRow('Customer Name', widget.rental.customerName),
            _buildRow('Item Rented', widget.rental.itemName),
            _buildRow('Delivery Resort', widget.rental.deliveryLocation),
            _buildRow('Terminal', widget.rental.terminalId),
            _buildRow('Payment Method', widget.rental.paymentMethod),
            _buildRow('Rental Fee', '₱${widget.rental.rateFee.toStringAsFixed(2)}'),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  '₱${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF57C00)),
                ),
              ],
            ),
            const Divider(height: 20),

            // Equipment QR Label Preview & Print Action
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${Uri.encodeComponent(_getQrCode(widget.rental))}',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.qr_code_2, size: 40, color: Color(0xFFF57C00)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getQrCode(widget.rental),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF9A3412),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Equipment QR Label',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFF57C00),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: () {
                      EquipmentQrLabelDialog.show(
                        context,
                        qrCode: _getQrCode(widget.rental),
                        itemName: widget.rental.itemName,
                        customerName: widget.rental.customerName,
                        rentalId: widget.rental.rentalId,
                      );
                    },
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print Label', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF57C00),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _isUpdating ? null : _confirmPayment,
          child: _isUpdating
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Confirm Received'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  String _getQrCode(RentalModel rental) {
    final matched = ItemModel.findByCode(rental.itemId) ?? ItemModel.findByCode(rental.itemName);
    if (matched != null && matched.qrCode != null && matched.qrCode!.isNotEmpty) {
      return matched.qrCode!;
    }
    return rental.itemId.isNotEmpty ? rental.itemId.toUpperCase() : 'SPORT-EQUIP-001';
  }
}
