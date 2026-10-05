import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alerts & Timers'), centerTitle: true),
        body: const Center(child: Text('Please log in to view active rental timers and alerts.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Live Timers'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Rental Countdown Timers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Live Timers for Active Rentals
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rentals')
                  .where('customerId', isEqualTo: user.uid)
                  .where('status', isEqualTo: 'active')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('No active rentals currently running timers.'),
                  );
                }

                final activeRentals = snapshot.data!.docs
                    .map((doc) => RentalModel.fromMap(doc.data() as Map<String, dynamic>, id: doc.id))
                    .toList();

                return Column(
                  children: activeRentals.map((rental) {
                    final now = DateTime.now();
                    final difference = rental.dueDate.difference(now);
                    final isOverdue = difference.isNegative;
                    final absDiff = difference.abs();

                    final hours = absDiff.inHours;
                    final minutes = absDiff.inMinutes % 60;
                    final seconds = absDiff.inSeconds % 60;

                    final timeString = '${hours.toString().padLeft(2, '0')}:'
                        '${minutes.toString().padLeft(2, '0')}:'
                        '${seconds.toString().padLeft(2, '0')}';

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isOverdue ? Colors.red.shade50 : Colors.blue.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isOverdue ? Colors.red.shade300 : Colors.blue.shade300,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rental.itemName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isOverdue ? Colors.red.shade900 : Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isOverdue ? 'STATUS: OVERDUE' : 'TIME REMAINING',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isOverdue ? Colors.red : Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isOverdue ? Colors.red : Colors.blueAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isOverdue ? '-$timeString' : timeString,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 24),
            const Text(
              'System Notification Center',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Notification Center List
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildNotificationTile(
                  Icons.check_circle,
                  Colors.green,
                  'Rental Request Approved',
                  'Your request for equipment has been verified by the operator.',
                  '10m ago',
                ),
                _buildNotificationTile(
                  Icons.lock_open,
                  Colors.blue,
                  'ESP32 Cabinet Unlocked',
                  'Terminal lock released successfully. Enjoy your equipment!',
                  '25m ago',
                ),
                _buildNotificationTile(
                  Icons.timer,
                  Colors.orange,
                  'Return Reminder',
                  'Return due in 15 minutes. Please proceed to the ESP32 terminal.',
                  '1h ago',
                ),
                _buildNotificationTile(
                  Icons.warning,
                  Colors.red,
                  'Overdue Penalty Notice',
                  'Late return policy applied (₱50/hr overdue rate).',
                  'Yesterday',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(IconData icon, Color color, String title, String body, String time) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(body, style: const TextStyle(fontSize: 12)),
        trailing: Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ),
    );
  }
}
