import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import 'esp32_verification_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final ItemModel item;

  const CheckoutScreen({
    super.key,
    required this.item,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _selectedHours = 1;
  late DateTime _startDate;
  late DateTime _dueDate;
  String _terminalId = 'TERM-01';
  String _deliveryLocation = 'ASRI Hotspring Resort';
  final _customResortController = TextEditingController();
  String _paymentMethod = 'QR'; // "QR" or "Cash"
  bool _isSubmitting = false;

  static const List<String> privateResorts = [
    'ASRI Hotspring Resort',
    '23 Prime Resort',
    'Springcrest Villa',
    'Casa Argela Hotspring Resort',
    'Kumo Villa',
    'El Stefano Hotspring Resort',
    'The Bloomfield Villa',
    'MYJC Resort',
    'Victoria Arya Hotspring Resort',
    'The House at Bluestone',
    'One Pansol Hotspring Resort',
    'Kasaya Private Resort',
    'The Pines Villas',
    'Villa Alyssa Hotspring Resort',
    'Casa Fides',
    'Other / Custom Resort',
  ];

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _dueDate = _startDate.add(Duration(hours: _selectedHours));
  }

  @override
  void dispose() {
    _customResortController.dispose();
    super.dispose();
  }

  void _updateDuration(int hours) {
    setState(() {
      _selectedHours = hours;
      _dueDate = _startDate.add(Duration(hours: hours));
    });
  }

  double get _baseFee => widget.item.rateHourly * _selectedHours;
  double get _deposit => widget.item.deposit;
  double get _totalInitialAmount => _baseFee + _deposit;

  Future<void> _submitRentalRequest() async {
    setState(() => _isSubmitting = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;

      if (user == null) throw Exception('User not logged in.');

      UserModel? userModel = await authService.getCurrentUserModel();

      final String newRentalId = FirebaseFirestore.instance.collection('rentals').doc().id;

      final String finalDeliveryLocation = _deliveryLocation == 'Other / Custom Resort'
          ? (_customResortController.text.trim().isNotEmpty
              ? _customResortController.text.trim()
              : 'Custom Private Resort')
          : _deliveryLocation;

      final rental = RentalModel(
        rentalId: newRentalId,
        itemId: widget.item.id,
        itemName: widget.item.name,
        customerId: user.uid,
        customerName: userModel?.name ?? user.email ?? 'Customer',
        terminalId: _terminalId,
        deliveryLocation: finalDeliveryLocation,
        startDate: _startDate,
        dueDate: _dueDate,
        rateFee: _baseFee,
        deposit: _deposit,
        paymentMethod: _paymentMethod,
        paymentConfirmedByAdmin: false,
        status: 'pending_esp32_rent',
        returnCondition: 'Good',
      );

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('rentals')
          .doc(newRentalId)
          .set(rental.toMap());

      // Update Item Status to 'rented'
      await FirebaseFirestore.instance
          .collection('items')
          .doc(widget.item.id)
          .set(
            widget.item.copyWith(status: 'rented').toMap(),
            SetOptions(merge: true),
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rental request submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Esp32VerificationScreen(rental: rental),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit rental: $e'),
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
        title: const Text('Start Rental'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Subtitle Header
            Text(
              'Start Rental Request',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Confirm the request details before sending it to the ESP32 terminal.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Physical Valid ID Notice Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.badge_outlined, color: Colors.blue.shade800, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Physical Valid ID Required: Renter must present 1 physical valid ID to the operator at the terminal upon pickup.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Item Banner Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 70,
                        width: 70,
                        color: Colors.grey.shade100,
                        child: widget.item.buildImage(fit: BoxFit.cover, height: 70, width: 70),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Category: ${widget.item.category}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Rate: ${widget.item.rateText}',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Duration Selector
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rental Duration',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [1, 2, 3, 5, 8].map((hours) {
                          final isSelected = _selectedHours == hours;
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              label: Text('$hours hr${hours > 1 ? 's' : ''}'),
                              selected: isSelected,
                              selectedColor: Theme.of(context).primaryColor,
                              backgroundColor: isDark ? const Color(0xFF131D2D) : Colors.white,
                              side: BorderSide(color: isDark ? const Color(0xFF1E2C42) : Colors.grey.shade300),
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : (isDark ? const Color(0xFFF8FAFC) : Colors.black87),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (_) => _updateDuration(hours),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Due Return Time:', style: TextStyle(fontSize: 13, color: Colors.black87)),
                        Text(
                          '${_dueDate.hour.toString().padLeft(2, '0')}:${_dueDate.minute.toString().padLeft(2, '0')} (${_dueDate.month}/${_dueDate.day})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Private Resort Delivery Location Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.location_on, color: Color(0xFFF57C00)),
                        SizedBox(width: 8),
                        Text(
                          'Delivery Location (Private Resort)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Select the private resort/villa where the operator will deliver your equipment:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _deliveryLocation,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: privateResorts.map((resort) {
                        return DropdownMenuItem<String>(
                          value: resort,
                          child: Text(resort, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _deliveryLocation = val);
                        }
                      },
                    ),
                    if (_deliveryLocation == 'Other / Custom Resort') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customResortController,
                        decoration: InputDecoration(
                          hintText: 'Enter Private Resort Name / Location',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Terminal Selection
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.developer_board, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'ESP32 Terminal:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    DropdownButton<String>(
                      value: _terminalId,
                      items: const [
                        DropdownMenuItem(value: 'TERM-01', child: Text('TERM-01 (Cabinet A)')),
                        DropdownMenuItem(value: 'TERM-02', child: Text('TERM-02 (Cabinet B)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _terminalId = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Rental Summary Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Breakdown',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const Divider(height: 20),
                    _buildCostRow('Base Rental Fee ($_selectedHours hrs)', '₱${_baseFee.toStringAsFixed(2)}'),
                    _buildCostRow('Security Deposit (Refundable)', '₱${_deposit.toStringAsFixed(2)}'),
                    const Divider(height: 20),
                    _buildCostRow(
                      'Total Initial Amount',
                      '₱${_totalInitialAmount.toStringAsFixed(2)}',
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Payment Method Selector
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Method',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: _paymentMethod,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _paymentMethod = value);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            title: const Row(
                              children: [
                                Icon(Icons.qr_code_2, color: Colors.blue),
                                SizedBox(width: 8),
                                Text('GCash / QR Code'),
                              ],
                            ),
                            value: 'QR',
                          ),
                          RadioListTile<String>(
                            title: const Row(
                              children: [
                                Icon(Icons.payments_outlined, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Cash to Operator'),
                              ],
                            ),
                            value: 'Cash',
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Operator / Admin will verify your payment before releasing the ESP32 cabinet lock.',
                              style: TextStyle(fontSize: 11, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Primary Action Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00), // Primary Orange
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: _isSubmitting ? null : _submitRentalRequest,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Submit Rental Request',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostRow(String title, String amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: isTotal ? 15 : 13,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: FontWeight.bold,
              color: isTotal ? const Color(0xFFF57C00) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
