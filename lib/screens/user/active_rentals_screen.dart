import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../models/item_model.dart';
import '../../services/auth_service.dart';
import '../shared/equipment_qr_label_dialog.dart';
import 'return_equipment_screen.dart';

class ActiveRentalsScreen extends StatelessWidget {
  const ActiveRentalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Active Rentals')),
        body: const Center(
          child: Text('Please log in to view your active rentals.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Active Rentals'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rentals')
            .where('customerId', isEqualTo: user.uid)
            .where('status', whereIn: ['active', 'pending_esp32_rent', 'pending_esp32_return'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 70, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'No Active Rentals',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your active gear rentals will appear here.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final rentals = snapshot.data!.docs
              .map((doc) => RentalModel.fromMap(doc.data() as Map<String, dynamic>, id: doc.id))
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rentals.length,
            itemBuilder: (context, index) {
              final rental = rentals[index];
              return _buildRentalCard(context, rental);
            },
          );
        },
      ),
    );
  }

  Widget _buildRentalCard(BuildContext context, RentalModel rental) {
    final now = DateTime.now();
    final isOverdue = now.isAfter(rental.dueDate);
    final diff = rental.dueDate.difference(now);

    String durationText;
    if (isOverdue) {
      durationText = 'OVERDUE by ${now.difference(rental.dueDate).inHours} hrs';
    } else {
      if (diff.inHours > 0) {
        durationText = '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
      } else {
        durationText = '${diff.inMinutes}m remaining';
      }
    }

    Color statusColor;
    if (rental.status == 'active') {
      statusColor = Colors.green;
    } else if (rental.status == 'pending_esp32_rent') {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.purple;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Item Name & Status Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    rental.itemName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    rental.status.toUpperCase().replaceAll('_', ' '),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Details
            _buildInfoRow('Delivery Resort', rental.deliveryLocation, valueColor: const Color(0xFFF57C00)),
            _buildInfoRow('Terminal ID', rental.terminalId),
            _buildInfoRow('Due Date', DateFormat('yyyy-MM-dd HH:mm').format(rental.dueDate)),
            _buildInfoRow(
              'Time Remaining',
              durationText,
              valueColor: isOverdue ? Colors.red : Colors.blue.shade800,
            ),
            _buildInfoRow('Security Deposit', '₱${rental.deposit.toStringAsFixed(2)}'),

            const SizedBox(height: 16),

            // Action Buttons: QR Code Pass & Return
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFF57C00), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final qrCode = _lookupQrCode(rental);
                        EquipmentQrLabelDialog.show(
                          context,
                          qrCode: qrCode,
                          itemName: rental.itemName,
                          customerName: rental.customerName,
                          rentalId: rental.rentalId,
                        );
                      },
                      icon: const Icon(Icons.qr_code_2, color: Color(0xFFF57C00)),
                      label: const Text(
                        'QR Pass',
                        style: TextStyle(
                          color: Color(0xFFF57C00),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReturnEquipmentScreen(rental: rental),
                          ),
                        );
                      },
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text(
                        'Start Return',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _lookupQrCode(RentalModel rental) {
    final matched = ItemModel.findByCode(rental.itemId) ?? ItemModel.findByCode(rental.itemName);
    if (matched != null && matched.qrCode != null && matched.qrCode!.isNotEmpty) {
      return matched.qrCode!;
    }
    return rental.itemId.isNotEmpty ? rental.itemId.toUpperCase() : 'SPORT-EQUIP-001';
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
