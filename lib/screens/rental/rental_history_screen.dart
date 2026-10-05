import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';

class RentalHistoryScreen extends StatefulWidget {
  final bool isAdmin;

  const RentalHistoryScreen({
    super.key,
    this.isAdmin = false,
  });

  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    Query query = FirebaseFirestore.instance.collection('rentals');

    if (!widget.isAdmin && user != null) {
      query = query.where('customerId', isEqualTo: user.uid);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'All Transactions (Admin)' : 'Rental History'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (widget.isAdmin)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: ['All', 'Active', 'Completed', 'Overdue'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: isSelected,
                      selectedColor: const Color(0xFFF57C00),
                      backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
                      side: BorderSide(color: isDark ? const Color(0xFF1E2C42) : Colors.grey.shade300),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? const Color(0xFFF8FAFC) : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() => _selectedFilter = filter),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No rental transaction records found.'),
                  );
                }

                List<RentalModel> rentals = snapshot.data!.docs
                    .map((doc) => RentalModel.fromMap(doc.data() as Map<String, dynamic>, id: doc.id))
                    .toList();

                if (widget.isAdmin && _selectedFilter != 'All') {
                  if (_selectedFilter == 'Active') {
                    rentals = rentals.where((r) => r.status == 'active').toList();
                  } else if (_selectedFilter == 'Completed') {
                    rentals = rentals.where((r) => r.status == 'completed').toList();
                  } else if (_selectedFilter == 'Overdue') {
                    rentals = rentals.where((r) => DateTime.now().isAfter(r.dueDate) && r.status == 'active').toList();
                  }
                }

                rentals.sort((a, b) => b.startDate.compareTo(a.startDate));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rentals.length,
                  itemBuilder: (context, index) {
                    final rental = rentals[index];
                    final isOverdue = DateTime.now().isAfter(rental.dueDate) && rental.status == 'active';
                    final statusDisplay = isOverdue ? 'Overdue' : rental.status;

                    Color statusColor = Colors.blue;
                    if (rental.status == 'completed') statusColor = Colors.green;
                    if (rental.status == 'active') statusColor = Colors.orange;
                    if (isOverdue) statusColor = Colors.red;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    rental.itemName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    statusDisplay.toUpperCase(),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            if (widget.isAdmin) ...[
                              _buildRow('Customer', rental.customerName),
                              _buildRow('Terminal ID', rental.terminalId),
                            ],
                            _buildRow('Rental ID', rental.rentalId.substring(0, 8).toUpperCase()),
                            _buildRow('Start Date', DateFormat('yyyy-MM-dd HH:mm').format(rental.startDate)),
                            _buildRow('Due Date', DateFormat('yyyy-MM-dd HH:mm').format(rental.dueDate)),
                            _buildRow('Payment Method', rental.paymentMethod),
                            _buildRow('Total Paid', '₱${(rental.rateFee + rental.deposit).toStringAsFixed(2)}'),
                            if (rental.latePenalty > 0)
                              _buildRow('Late Penalty', '₱${rental.latePenalty.toStringAsFixed(2)}', isRed: true),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isRed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isRed ? Colors.red : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
