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
                '• Confirm the delivery location and return arrangements with the operator.\n'
                '• The rental timer starts when the operator hands over the item. Return it by the due time shown in My Rentals.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('2. ID Verification'),
              _buildSectionText(
                '• A valid Government or Student ID photo must be uploaded to your profile.\n'
                '• Review the rental price shown at checkout.\n'
                '• The admin records payments and refunds after inspection and settlement.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('3. Damaged & Lost Items Policy'),
              _buildSectionText(
                '• The admin checks the equipment and included accessories at release and return.\n'
                '• Late fees use the saved rental rate. Damage or missing-part charges are recorded with a reason after inspection.',
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('4. Delivery & Return Verification'),
              _buildSectionText(
                '• Show your rental handoff QR to the operator when the item is delivered.\n'
                '• The operator scans the equipment QR at the shop before delivery, then scans your rental QR at the resort to start the timer.\n'
                '• On return, the admin records physical receipt to stop the timer, then completes inspection.',
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
