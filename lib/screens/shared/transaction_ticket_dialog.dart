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
        constraints: BoxConstraints(
            maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * .84),
        title: const Text('Your rental handoff QR'),
        content: SizedBox(
            width: 340,
            child: FutureBuilder<Map<String, dynamic>>(
              future: _ticket,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final alreadyHandedOff = widget.rental.isActive ||
                      widget.rental.isAwaitingInspection ||
                      widget.rental.hasPendingReturnRequest;
                  return RentalNotice(
                      isError: true,
                      title: alreadyHandedOff
                          ? 'Handoff QR no longer available'
                          : 'Ticket unavailable',
                      message: alreadyHandedOff
                          ? 'This rental has already been handed off. Use the return status on My Rentals; the admin records the return with the rental code.'
                          : '${snapshot.error}',
                      action: TextButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again')));
                }
                if (!snapshot.hasData)
                  return const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()));
                final data = snapshot.data!;
                final status = data['status']?.toString() ??
                    widget.rental.normalizedStatus;
                final expiry = DateTime.tryParse(
                    data['hold_expires_at']?.toString() ?? '');
                final expired = status == 'APPROVED' &&
                    expiry != null &&
                    DateTime.now().isAfter(expiry);
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
                  if (status == 'APPROVED' &&
                      !expired &&
                      image.startsWith('data:image/png;base64,'))
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
                                  content: Text('Rental code copied.')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy rental code')),
                  if (expiry != null)
                    Text(
                        '${status == 'PENDING_ADMIN_APPROVAL' ? 'Review hold ends' : 'Handoff before'} ${DateFormat('MMM d · h:mm a').format(expiry.toLocal())}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13)),
                  const SizedBox(height: 14),
                  RentalNotice(
                      title: expired
                          ? 'This hold has ended'
                          : widget.rental.isRentAndPlayPickup
                              ? 'Ipakita sa Rent & Play'
                              : 'Ipakita sa delivery staff',
                      isError: expired,
                      message: expired
                          ? 'Close this ticket and refresh My Rentals to check your rental request.'
                          : status == 'PENDING_ADMIN_APPROVAL'
                              ? 'Nire-review pa ang request. Magsisimula lang ang rental time kapag naiabot na sa iyo ang item sa ${widget.rental.customerHandoffLocation}.'
                              : widget.rental.isRentAndPlayPickup
                                  ? 'Pumunta sa Rent & Play sa ASRI. Dalhin ang valid ID; i-scan ng staff ang QR kapag ibinigay na sa iyo ang item.'
                                  : 'Dalhin ang valid ID. I-scan ng delivery staff ang QR kapag iniabot na sa iyo ang item sa ${widget.rental.customerHandoffLocation}.'),
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
