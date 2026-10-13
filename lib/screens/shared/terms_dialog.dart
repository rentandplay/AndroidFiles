import 'package:flutter/material.dart';

const String rentalTermsVersion = '2026-10-13-v1';

class TermsDialog extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback? onDecline;

  const TermsDialog({
    super.key,
    required this.onAccept,
    this.onDecline,
  });

  static Future<bool?> show(BuildContext context,
      {required VoidCallback onAccept, VoidCallback? onDecline}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TermsDialog(
        onAccept: onAccept,
        onDecline: onDecline,
      ),
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
                'Please read these rental terms before creating your Rent & Play account.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildSectionTitle('1. Account details'),
              _buildSectionText(
                'Provide accurate name and contact details, and keep your password and verification codes private. Use your account for your own rental requests.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('2. Rental requests and charges'),
              _buildSectionText(
                'A rental request is not confirmed until its status is approved in the app. Before submitting, review the item, rental duration, due time, rental fee, and any deposit or payment instructions shown at checkout. Late fees use the rates shown in the app.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('3. ID and handoff'),
              _buildSectionText(
                'Show the required physical Government or Student ID to the admin during handoff. The rental timer starts when the admin verifies and releases the equipment. Check the item and included accessories with the admin.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('4. Return, inspection, and extra charges'),
              _buildSectionText(
                'Return the same equipment and all included accessories by the due time. A return request alone does not stop the timer; it stops when the admin records physical receipt. The admin inspects the returned item. Late returns, damage, loss, or missing accessories may result in additional charges, which should be recorded with an inspection reason.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('5. Personal information'),
              _buildSectionText(
                'Your name, email, phone number, and ID verification details are used to manage your account, verify rental handoffs, and communicate about rentals and returns. Please provide only accurate information needed for these purposes.',
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
