import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/esp32_service.dart';
import '../shared/waiting_esp32_screen.dart';

class ReturnEquipmentScreen extends StatefulWidget {
  final RentalModel rental;

  const ReturnEquipmentScreen({
    super.key,
    required this.rental,
  });

  @override
  State<ReturnEquipmentScreen> createState() => _ReturnEquipmentScreenState();
}

class _ReturnEquipmentScreenState extends State<ReturnEquipmentScreen> {
  String _selectedCondition = 'Good'; // "Good", "Needs Check", "Damaged"
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  late DateTime _returnTimestamp;
  late double _latePenalty;

  @override
  void initState() {
    super.initState();
    _returnTimestamp = DateTime.now();
    _latePenalty = _calculateLatePenalty();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double _calculateLatePenalty() {
    if (_returnTimestamp.isAfter(widget.rental.dueDate)) {
      final overdueHours = _returnTimestamp.difference(widget.rental.dueDate).inHours + 1;
      return overdueHours * 50.0; // ₱50 per hour overdue
    }
    return 0.0;
  }

  Future<void> _submitReturnRequest() async {
    setState(() => _isSubmitting = true);

    try {
      final esp32Service = Provider.of<Esp32Service>(context, listen: false);

      final updatedRental = widget.rental.copyWith(
        status: 'pending_esp32_return',
        returnCondition: _selectedCondition,
        conditionNotes: _notesController.text.trim(),
        latePenalty: _latePenalty,
        returnedDate: _returnTimestamp,
      );

      // Update Firestore Rental Document
      await FirebaseFirestore.instance
          .collection('rentals')
          .doc(widget.rental.rentalId)
          .update({
        'status': 'pending_esp32_return',
        'returnCondition': _selectedCondition,
        'conditionNotes': _notesController.text.trim(),
        'latePenalty': _latePenalty,
        'returnedDate': Timestamp.fromDate(_returnTimestamp),
      });

      // Trigger ESP32 Return Ready State
      await esp32Service.initiateReturnHardwareVerification(
        widget.rental.terminalId,
        widget.rental.rentalId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Return request submitted. Please return gear to cabinet.'),
          backgroundColor: Colors.blue,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingEsp32Screen(
            rental: updatedRental,
            isReturn: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit return request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Return Equipment'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Header
            Text(
              'Equipment Return',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Specify equipment condition and place the item inside the ESP32 cabinet.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Item Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.rental.itemName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const Divider(height: 20),
                    _buildRow('Rental ID', widget.rental.rentalId.substring(0, 8).toUpperCase()),
                    _buildRow('Terminal ID', widget.rental.terminalId),
                    _buildRow('Due Return Date', DateFormat('yyyy-MM-dd HH:mm').format(widget.rental.dueDate)),
                    _buildRow('Returned At', DateFormat('yyyy-MM-dd HH:mm').format(_returnTimestamp)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Equipment Condition Selector
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Equipment Condition',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['Good', 'Needs Check', 'Damaged'].map((condition) {
                          final isSelected = _selectedCondition == condition;
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          Color chipColor = Colors.green;
                          if (condition == 'Needs Check') chipColor = Colors.orange;
                          if (condition == 'Damaged') chipColor = Colors.red;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text(condition),
                              selected: isSelected,
                              selectedColor: chipColor,
                              backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
                              side: BorderSide(color: isDark ? const Color(0xFF1E2C42) : Colors.grey.shade300),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : (isDark ? const Color(0xFFF8FAFC) : Colors.black87),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (_) {
                                setState(() => _selectedCondition = condition);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Condition Notes Text Field
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Condition Notes (Optional)',
                        hintText: 'e.g., Minor scratch on handlebar or missing 1 chess pawn',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Overtime / Late Return Fee Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _latePenalty > 0 ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _latePenalty > 0 ? Colors.red.shade300 : Colors.green.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _latePenalty > 0 ? Icons.error_outline : Icons.check_circle_outline,
                    color: _latePenalty > 0 ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _latePenalty > 0 ? 'Overdue Late Penalty Applied' : 'On-Time Return',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _latePenalty > 0 ? Colors.red.shade800 : Colors.green.shade800,
                          ),
                        ),
                        Text(
                          _latePenalty > 0
                              ? 'Penalty: ₱${_latePenalty.toStringAsFixed(2)} (Overdue rate: ₱50/hr)'
                              : 'No late return penalty applied (₱0.00). Deposit will be refunded upon check.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _latePenalty > 0 ? Colors.red.shade900 : Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Primary Red Return Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: _isSubmitting ? null : _submitReturnRequest,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Submit Return Request',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
