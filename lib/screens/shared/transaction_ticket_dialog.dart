import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';

class TransactionTicketDialog {
  static Future<void> show(BuildContext context, RentalModel rental) =>
      showDialog<void>(
        context: context,
        builder: (_) => BookingTicket(rental: rental),
      );
}

class BookingTicket extends StatefulWidget {
  const BookingTicket({super.key, required this.rental, this.api});
  final RentalModel rental;
  final MobileApiService? api;
  @override
  State<BookingTicket> createState() => _BookingTicketState();
}

class _BookingTicketState extends State<BookingTicket> {
  late Future<Map<String, dynamic>> _ticket;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _ticket = (widget.api ?? MobileApiService.instance)
        .rentalTicket(widget.rental.rentalId);
  }

  void _retry() => setState(_load);
  @override
  Widget build(BuildContext context) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Your booking QR'),
        content: SizedBox(
            width: 340,
            child: FutureBuilder<Map<String, dynamic>>(
              future: _ticket,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return RentalNotice(
                      isError: true,
                      title: 'Ticket unavailable',
                      message: '${snapshot.error}',
                      action: TextButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again')));
                if (!snapshot.hasData)
                  return const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()));
                final data = snapshot.data!;
                final status = data['status']?.toString() ??
                    widget.rental.normalizedStatus;
                final expiry = DateTime.tryParse(
                    data['hold_expires_at']?.toString() ?? '');
                final expired =
                    expiry != null && DateTime.now().isAfter(expiry);
                final image = data['image_data_url']?.toString() ?? '';
                final code =
                    data['rental_code']?.toString() ?? widget.rental.rentalCode;
                return SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.rental.itemName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  RentalStatusBadge(status: status),
                  const SizedBox(height: 16),
                  if (!expired && image.startsWith('data:image/png;base64,'))
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 270),
                        child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                                padding: const EdgeInsets.all(12),
                                color: Colors.white,
                                child: Image.memory(
                                    base64Decode(image.split(',').last),
                                    fit: BoxFit.contain)))),
                  const SizedBox(height: 12),
                  SelectableText(code,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, letterSpacing: 1)),
                  TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Booking code copied.')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy booking code')),
                  if (expiry != null)
                    Text(
                        '${status == 'PENDING_ADMIN_APPROVAL' ? 'Review hold ends' : 'Pickup before'} ${DateFormat('MMM d · h:mm a').format(expiry.toLocal())}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13)),
                  const SizedBox(height: 14),
                  RentalNotice(
                      title: expired
                          ? 'This hold has ended'
                          : 'Show this to the admin',
                      isError: expired,
                      message: expired
                          ? 'Close this ticket and refresh My Rentals to check your booking.'
                          : status == 'PENDING_ADMIN_APPROVAL'
                              ? 'The admin will review your booking first. The rental clock starts at physical handoff.'
                              : 'Bring one valid ID. The admin will scan this QR, verify your equipment and confirm the handoff.'),
                ]));
              },
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      );
}
