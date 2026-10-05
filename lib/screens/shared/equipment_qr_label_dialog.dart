import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EquipmentQrLabelDialog extends StatelessWidget {
  final String qrCode;
  final String itemName;
  final String? customerName;
  final String? rentalId;

  const EquipmentQrLabelDialog({
    super.key,
    required this.qrCode,
    required this.itemName,
    this.customerName,
    this.rentalId,
  });

  static Future<void> show(
    BuildContext context, {
    required String qrCode,
    required String itemName,
    String? customerName,
    String? rentalId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => EquipmentQrLabelDialog(
        qrCode: qrCode,
        itemName: itemName,
        customerName: customerName,
        rentalId: rentalId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanQrCode = qrCode.trim().isNotEmpty ? qrCode.trim() : 'RENT-PLAY-ITEM';
    final qrImageUrl =
        'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${Uri.encodeComponent(cleanQrCode)}';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.all(20),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: Color(0xFFF57C00), size: 28),
              SizedBox(width: 8),
              Text(
                'Equipment QR Label',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Official Rent & Play Equipment Label (50 × 30 mm)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Physical Sticker Card Design (50x30mm proportion)
            Container(
              width: 320,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // QR Image
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        qrImageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.qr_code_2, size: 60, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Label Text & Branding
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cleanQrCode,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customerName != null && customerName!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Renter: $customerName',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC2410C),
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),

                        // Rent & Play Logo / Brand Badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF57C00),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'RENT & PLAY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: cleanQrCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('QR Code "$cleanQrCode" copied!')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Code'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF57C00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Sending QR Label "$cleanQrCode" to printer...'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Print Label'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
