import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/item_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/sign_in_prompt.dart';
import '../auth/id_verification_screen.dart';
import 'checkout_screen.dart';

class ItemDetailsScreen extends StatelessWidget {
  final ItemModel item;

  const ItemDetailsScreen({
    super.key,
    required this.item,
  });

  Future<void> _continueToRental(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      await showSignInPrompt(context);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    UserModel? userModel;
    try {
      userModel = await authService.getCurrentUserModel();
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (!context.mounted) return;

    if (userModel == null ||
        userModel.validIdUrl?.isNotEmpty != true ||
        !userModel.hasAcceptedTerms) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Please review rental policies and complete your profile before renting.',
          ),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IdVerificationScreen(userModel: userModel),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CheckoutScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAvailable = item.status.toLowerCase() == 'available';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Equipment Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main Equipment Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Item Image using buildImage() fallback loader
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        color: Colors.grey.shade100,
                        child: item.buildImage(fit: BoxFit.contain, height: 180),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title & Category
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.category,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Status Pill & Terminal ID
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isAvailable ? Colors.green.shade100 : Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.status.toUpperCase(),
                            style: TextStyle(
                              color: isAvailable ? Colors.green.shade800 : Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code, size: 14, color: Colors.blue),
                              const SizedBox(width: 4),
                              Text(
                                item.qrCode != null ? 'QR: ${item.qrCode}' : 'ID: ${item.id.toUpperCase()}',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Description Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Equipment Description',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(
                      item.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Rental Terms Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Rental Rates & Terms',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildDetailRow('Standard Package Rate', item.rateText),
                    if (item.specialRate != null)
                      _buildDetailRow('Special Package Rate', item.specialRate!),
                    if (item.isForSale && item.salePrice != null)
                      _buildDetailRow('Option to Buy', '₱${item.salePrice!.toStringAsFixed(0)}'),
                    _buildDetailRow(
                      'Required Security Deposit',
                      '₱${item.deposit.toStringAsFixed(0)}',
                      highlight: item.deposit >= 300,
                    ),
                    _buildDetailRow(
                      'Late Return Penalty',
                      '₱${item.latePenalty.toStringAsFixed(0)} / hour overdue',
                    ),
                    if (item.category == 'Board Games' || item.category == 'Cards')
                      _buildDetailRow(
                        'Missing Parts Penalty',
                        '₱50 / lost piece',
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Physical Valid ID Notice Banner (Rule 1)
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
                      'Valid ID required: show one physical ID to the operator when the rented item is handed over at your selected location.',
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

            // Notice Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber.shade900, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Send a rental request and wait for payment review and approval. The operator prepares the item at the shop, then scans your rental QR when the item reaches your selected location. Your rental timer starts at that handoff.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Orange Primary Button
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
                onPressed:
                    isAvailable ? () => _continueToRental(context) : null,
                child: const Text(
                  'Continue to Rental',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String title, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.red.shade700 : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
