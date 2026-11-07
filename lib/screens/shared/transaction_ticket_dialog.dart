import '../../services/server_clock.dart';
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
                if (!snapshot.hasData) {
                  return const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()));
                }
                final data = snapshot.data!;
                final status = data['status']?.toString() ??
                    widget.rental.normalizedStatus;
                final expiry = DateTime.tryParse(
                    data['hold_expires_at']?.toString() ?? '');
                final expired = status == 'APPROVED' &&
                    expiry != null &&
                    ServerClock.instance.now.isAfter(expiry);
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
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Rental code copied.')));
                        }
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
                              ? 'Show this to Rent & Play'
                              : 'Show this to delivery staff',
                      isError: expired,
                      message: expired
                          ? 'Close this ticket and refresh My Rentals to check your rental request.'
                          : status == 'PENDING_ADMIN_APPROVAL'
                              ? 'Your request is still under review. Rental time starts only when staff hands the item over to you at ${widget.rental.customerHandoffLocation}.'
                              : widget.rental.isRentAndPlayPickup
                                  ? 'Show your rental QR code and a valid ID to staff at ${widget.rental.customerHandoffLocation} for shop handover.'
                                  : 'Bring a valid ID. Delivery staff will scan the QR code when they hand over your item at ${widget.rental.customerHandoffLocation}.'),
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

class EmbeddedRentalHandoffQr extends StatefulWidget {
  const EmbeddedRentalHandoffQr({
    super.key,
    required this.rental,
    this.api,
  });

  final RentalModel rental;
  final MobileApiService? api;

  @override
  State<EmbeddedRentalHandoffQr> createState() =>
      _EmbeddedRentalHandoffQrState();
}

class _EmbeddedRentalHandoffQrState extends State<EmbeddedRentalHandoffQr> {
  late Future<Map<String, dynamic>> _ticketFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EmbeddedRentalHandoffQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rental.rentalId != widget.rental.rentalId ||
        oldWidget.rental.deliveryStatus != widget.rental.deliveryStatus) {
      _load();
    }
  }

  void _load() {
    _ticketFuture = (widget.api ?? MobileApiService.instance)
        .rentalTicket(widget.rental.rentalId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _ticketFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.error.withValues(alpha: .3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: scheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QR code ticket unavailable: ${snapshot.error}',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
                TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Container(
            height: 110,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.primary)),
                const SizedBox(height: 8),
                Text('Loading live handoff QR & rolling PIN...',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        final status =
            data['status']?.toString() ?? widget.rental.normalizedStatus;
        final expiry =
            DateTime.tryParse(data['hold_expires_at']?.toString() ?? '');
        final expired = status == 'APPROVED' &&
            expiry != null &&
            ServerClock.instance.now.isAfter(expiry);
        final image = data['image_data_url']?.toString() ?? '';
        final code =
            data['rental_code']?.toString() ?? widget.rental.rentalCode;
        final rollingPin = data['rolling_pin']?.toString() ?? '';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary.withValues(alpha: .3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE HANDOVER QR & PIN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!expired && image.startsWith('data:image/png;base64,'))
                Container(
                  width: 175,
                  height: 175,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Image.memory(
                    base64Decode(image.split(',').last),
                    fit: BoxFit.contain,
                  ),
                ),
              const SizedBox(height: 10),
              if (rollingPin.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: .25)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '6-DIGIT ROLLING PIN',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        rollingPin,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              SelectableText(
                'Rental code: $code',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.rental.isRentAndPlayPickup
                    ? 'Show this QR or 6-digit PIN at the counter to start your rental timer.'
                    : 'Show this QR or 6-digit PIN to the delivery rider at ${widget.rental.deliveryLocation}. Timer starts upon scan.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}
