import 'package:flutter/material.dart';

class TermsDialog extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback? onDecline;

  const TermsDialog({
    super.key,
    required this.onAccept,
    this.onDecline,
  });

  static Future<bool?> show(BuildContext context, {required VoidCallback onAccept}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TermsDialog(onAccept: onAccept),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.gavel_rounded, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          const Text('Terms & Conditions'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Welcome to Rent and Play! Please review and accept our rental terms before proceeding.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildSectionTitle('1. Operating Hours'),
              _buildSectionText(
                '• Business & Terminal Operating Hours: 8:00 AM – 8:00 PM daily.\n'
                '• All same-day rental items must be returned by 8:00 PM sharp to avoid overnight late penalties.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('2. ID Verification & Security Deposit'),
              _buildSectionText(
                '• A valid Government or Student ID photo must be uploaded to your profile.\n'
                '• High-value rentals (Bicycles, Gaming Consoles like PS5) require a refundable security deposit (e.g. ₱500 for PS5).\n'
                '• Deposits are refunded upon inspection and safe return of the item.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('3. Damaged & Lost Items Policy'),
              _buildSectionText(
                '• Lost board game or card set pieces incur a fixed penalty of ₱50 per piece.\n'
                '• Damaged gear, broken consoles, or unreturned items will forfeit the security deposit and may incur additional charges up to the full replacement value of the item.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('4. ESP32 Smart Cabinet & Unlock Safety'),
              _buildSectionText(
                '• Equipment is stored in ESP32-controlled smart cabinets.\n'
                '• Lockers will unlock automatically upon Admin payment confirmation or valid QR code scan.\n'
                '• Ensure the cabinet door is securely shut after retrieving or returning your item.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            if (onDecline != null) onDecline!();
          },
          child: const Text('Decline', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            onAccept();
            Navigator.of(context).pop(true);
          },
          child: const Text('Accept & Agree'),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
    );
  }

  Widget _buildSectionText(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
      ),
    );
  }
}
