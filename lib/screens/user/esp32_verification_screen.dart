import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/rental_model.dart';
import 'customer_home_screen.dart';

class Esp32VerificationScreen extends StatelessWidget {
  final RentalModel rental;

  const Esp32VerificationScreen({
    super.key,
    required this.rental,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Terminal Unlock'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rentals')
            .doc(rental.rentalId)
            .snapshots(),
        builder: (context, snapshot) {
          RentalModel currentRental = rental;
          if (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.data() != null) {
            currentRental = RentalModel.fromMap(
              snapshot.data!.data() as Map<String, dynamic>,
              id: snapshot.data!.id,
            );
          }

          final isUnlocked = currentRental.status == 'active' ||
              currentRental.paymentConfirmedByAdmin;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),

                // Status Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isUnlocked
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUnlocked ? Icons.lock_open : Icons.hourglass_top,
                    size: 80,
                    color: isUnlocked ? Colors.green : Colors.orange,
                  ),
                ),

                const SizedBox(height: 24),

                // Status Title & Subtitle
                Text(
                  isUnlocked
                      ? 'Cabinet Unlocked!'
                      : 'Awaiting Payment & Unlock',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                Text(
                  isUnlocked
                      ? 'The ESP32 Smart Cabinet door is open. Please retrieve your ${currentRental.itemName}.'
                      : 'Your request for ${currentRental.itemName} is sent to Terminal ${currentRental.terminalReference}. Admin is reviewing payment.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),

                const SizedBox(height: 32),

                // Rental Details Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRow('Rental ID', currentRental.displayReference),
                        _buildRow('Item Name', currentRental.itemName),
                        _buildRow('Terminal', currentRental.terminalReference),
                        _buildRow(
                            'Payment Method', currentRental.paymentMethod),
                        _buildRow(
                          'Total Fee',
                          '₱${currentRental.rateFee.toStringAsFixed(2)}',
                        ),
                        _buildRow('Status', currentRental.status.toUpperCase(),
                            isStatus: true),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Return Home Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CustomerHomeScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text(
                      'Back to Home Catalog',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isStatus ? Colors.orange.shade800 : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
