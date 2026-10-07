import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import '../auth/login_screen.dart';
import '../shared/transaction_ticket_dialog.dart';
import 'return_equipment_screen.dart';

class ActiveRentalsScreen extends StatefulWidget {
  const ActiveRentalsScreen({super.key, this.onBrowse});
  final VoidCallback? onBrowse;
  @override
  State<ActiveRentalsScreen> createState() => _ActiveRentalsScreenState();
}

class _ActiveRentalsScreenState extends State<ActiveRentalsScreen> {
  List<RentalModel>? _rentals;
  Timer? _poll;
  bool _refreshing = false;
  String _error = '', _filter = 'All';
  final _cancelling = <String>{};
  final _uploadingProof = <String>{};
  @override
  void initState() {
    super.initState();
    _refreshRentals();
    _poll =
        Timer.periodic(const Duration(seconds: 20), (_) => _refreshRentals());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshRentals() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final next = await MobileApiService.instance.listRentals();
      if (mounted)
        setState(() {
          _rentals = next;
          _error = '';
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _refreshing = false;
    }
  }

  bool _matches(RentalModel rental) => switch (_filter) {
        'Review' => rental.isPendingAdminReview,
        'Pickup' => rental.isAwaitingPickup,
        'In use' => rental.isActive,
        'Inspection' => rental.isAwaitingInspection,
        _ => true,
      };

  int _countForFilter(String filter, List<RentalModel> rentals) =>
      filter == 'All' ? rentals.length : rentals.where((rental) {
        return switch (filter) {
          'Review' => rental.isPendingAdminReview,
          'Pickup' => rental.isAwaitingPickup,
          'In use' => rental.isActive,
          'Inspection' => rental.isAwaitingInspection,
          _ => false,
        };
      }).length;

  void _openBrowse() {
    widget.onBrowse?.call();
  }

  Future<void> _cancelBooking(RentalModel rental) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Cancel this rental request?'),
              content: const Text(
                  'The equipment hold will be released. Any verified payment remains recorded for refund.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep request')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Cancel request')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling.add(rental.rentalId));
    try {
      await MobileApiService.instance.cancelRental(rental.rentalId);
      if (mounted) await _refreshRentals();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _cancelling.remove(rental.rentalId));
    }
  }

  Future<void> _uploadPaymentProof(RentalModel rental) async {
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1800, imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 350000) {
        throw const MobileApiException('Choose a screenshot under 350 KB.');
      }
      final isPng = bytes.length >= 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71;
      final isJpeg = bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      if (!isPng && !isJpeg) {
        throw const MobileApiException('Choose a PNG or JPEG screenshot.');
      }
      setState(() => _uploadingProof.add(rental.rentalId));
      await MobileApiService.instance.submitPaymentProof(
          rentalId: rental.rentalId,
          imageDataUrl:
              'data:image/${isPng ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}',
          reference: rental.paymentProofReference);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment screenshot sent for owner review.')));
        await _refreshRentals();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _uploadingProof.remove(rental.rentalId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final open = (_rentals ?? []).where((rental) => rental.isOpen).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final visible = open.where(_matches).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('My Rentals'), actions: [
        IconButton(
            tooltip: 'Refresh rentals',
            onPressed: _refreshRentals,
            icon: const Icon(Icons.refresh)),
      ]),
      body: user == null
          ? RentalEmptyState(
              title: 'Sign in to view rentals',
              message:
                  'Your rental requests and equipment in use will appear here.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in'),
              ),
            )
          : _rentals == null && _error.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refreshRentals,
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_error.isNotEmpty) ...[
                          RentalNotice(
                              isError: true,
                              title: _rentals == null
                                  ? 'Could not load rentals'
                                  : 'Could not refresh rentals',
                              message: _rentals == null
                                  ? _error
                                  : 'Showing your last loaded records. Pull down to retry.',
                              action: TextButton(
                                  onPressed: _refreshRentals,
                                  child: const Text('Try again'))),
                          const SizedBox(height: 16),
                        ],
                        if (open.isNotEmpty) ...[
                          Text(
                              '${open.length} open rental${open.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                              'Follow payment review, delivery and return in one place.',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(height: 14),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final label in [
                              'All',
                              'Review',
                              'Pickup',
                              'In use',
                              'Inspection'
                            ])
                              ChoiceChip(
                                  label: Text(
                                      '$label (${_countForFilter(label, open)})'),
                                  selected: label == _filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = label)),
                          ]),
                          const SizedBox(height: 16),
                        ],
                        if (visible.isEmpty && _rentals != null)
                          RentalEmptyState(
                            title: open.isEmpty
                                ? 'No open rentals yet'
                                : 'Nothing in this stage',
                            message: open.isEmpty
                                ? 'Choose equipment from the catalog to send a rental request.'
                                : 'Try another filter to see your other rentals.',
                            action: open.isNotEmpty
                                ? TextButton(
                                    onPressed: () =>
                                        setState(() => _filter = 'All'),
                                    child: const Text('Show all rentals'))
                                : widget.onBrowse == null
                                    ? null
                                    : FilledButton.icon(
                                        onPressed: _openBrowse,
                                        icon: const Icon(
                                            Icons.storefront_outlined),
                                        label: const Text('Browse equipment'),
                                      ),
                          ),
                        for (final rental in visible)
                          RentalBookingCard(
                            rental: rental,
                            onTicket: () =>
                                TransactionTicketDialog.show(context, rental),
                            onUploadPaymentProof:
                                _uploadingProof.contains(rental.rentalId)
                                    ? null
                                    : () => _uploadPaymentProof(rental),
                            onCancel: _cancelling.contains(rental.rentalId)
                                ? null
                                : () => _cancelBooking(rental),
                            onReturn: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ReturnEquipmentScreen(
                                          rental: rental)));
                              if (mounted) _refreshRentals();
                            },
                            onRefresh: _refreshRentals,
                          ),
                      ]),
                ),
    );
  }
}

class RentalBookingCard extends StatelessWidget {
  const RentalBookingCard(
      {super.key,
      required this.rental,
      this.onTicket,
      this.onCancel,
      this.onReturn,
      this.onUploadPaymentProof,
      this.onRefresh});
  final RentalModel rental;
  final VoidCallback? onTicket, onCancel, onReturn, onRefresh,
      onUploadPaymentProof;
  String _date(DateTime value) =>
      DateFormat('MMM d · h:mm a').format(value.toLocal());
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final holdEnded = rental.canCancel &&
        rental.holdExpiresAt != null &&
        now.isAfter(rental.holdExpiresAt!);
    final hasDueDate = rental.dueDate.millisecondsSinceEpoch > 0;
    final overdue =
        rental.isActive && hasDueDate && now.isAfter(rental.dueDate);
    final minutes = rental.dueDate.difference(now).inMinutes.abs();
    final time = minutes >= 60
        ? '${minutes ~/ 60}h ${minutes % 60}m'
        : '${minutes < 1 ? 1 : minutes}m';
    final (heading, message) = holdEnded
        ? (
            'Hold ended',
            'Refresh to check the latest status before sending another rental request.'
          )
        : rental.isPendingAdminReview
            ? (
                'Waiting for admin approval',
                'Your rental request is being reviewed. The rental clock has not started.'
              )
            : rental.isAwaitingPickup
                ? (
                    rental.deliveryStatus == 'PREPARED'
                        ? 'Ready for delivery'
                        : 'Rental request approved',
                    rental.deliveryStatus == 'PREPARED'
                        ? 'The operator is preparing delivery to ${rental.deliveryLocation}. Show your rental QR and valid ID at handoff.'
                        : 'The operator is checking the assigned unit before delivery to ${rental.deliveryLocation}. The rental clock has not started.'
                  )
                : rental.isAwaitingInspection
                    ? (
                        'Equipment received',
                        'Your rental clock has stopped. The admin is checking condition and final charges.'
                      )
                    : rental.hasPendingReturnRequest
                        ? (
                            'Bring the item back to the admin',
                            'Your return request is sent. The clock stops when the admin records physical receipt.'
                          )
                        : rental.isActive
                            ? (
                                overdue
                                    ? 'Overdue by $time'
                                    : hasDueDate
                                        ? '$time remaining'
                                        : 'Return time not recorded',
                                'Return the equipment to the admin before your due time.'
                              )
                            : (
                                'Awaiting confirmation',
                                'Ask the admin to confirm the current status of this rental.'
                              );
    return RentalSection(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(rental.itemName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(rental.rentalCode.isEmpty ? rental.rentalId : rental.rentalCode,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 10),
      Align(
          alignment: Alignment.centerLeft,
          child: RentalStatusBadge(status: rental.normalizedStatus)),
      const SizedBox(height: 14),
      RentalNotice(
          title: heading,
          message: message,
          isError: holdEnded || overdue,
          icon: overdue
              ? Icons.schedule
              : rental.isAwaitingInspection
                  ? Icons.task_alt
                  : Icons.info_outline),
      const SizedBox(height: 12),
      RentalValueRow('Pickup / resort', rental.deliveryLocation),
      if (rental.paymentMethod.toUpperCase() == 'QR' &&
          rental.paymentProofStatus == 'PENDING_REVIEW')
        const RentalNotice(
            title: 'Payment screenshot under review',
            message:
                'The owner will verify the InstaPay transfer before approving your rental request.'),
      if (rental.paymentMethod.toUpperCase() == 'QR' &&
          rental.paymentProofStatus == 'REJECTED')
        RentalNotice(
            title: 'Upload a corrected payment screenshot',
            message: rental.paymentProofNote.isEmpty
                ? 'The owner could not verify the transfer. Upload a clear screenshot of the successful payment.'
                : rental.paymentProofNote,
            isError: true),
      if (rental.holdExpiresAt != null && rental.canCancel)
        RentalValueRow(
            rental.isPendingAdminReview ? 'Review hold ends' : 'Handoff before',
            _date(rental.holdExpiresAt!)),
      if (rental.isActive)
        RentalValueRow(
            'Return by', hasDueDate ? _date(rental.dueDate) : 'Ask the admin'),
      if (rental.receivedAt != null)
        RentalValueRow('Received', _date(rental.receivedAt!)),
      RentalValueRow('Rental fee', rentalMoney(rental.rateFee)),
      RentalValueRow('Security deposit', rentalMoney(rental.deposit)),
      if (rental.balanceDue > 0 && !rental.canCancel)
        RentalValueRow('Balance due', rentalMoney(rental.balanceDue)),
      if (rental.refundDue > 0)
        RentalValueRow('Refund due', rentalMoney(rental.refundDue)),
      if (rental.isAwaitingPickup) ...[
        const SizedBox(height: 14),
        FilledButton.icon(
            onPressed: onTicket,
            icon: const Icon(Icons.qr_code),
            label: const Text('Show rental handoff QR')),
      ],
      if (rental.paymentMethod.toUpperCase() == 'QR' &&
          rental.paymentProofStatus == 'REJECTED')
        OutlinedButton.icon(
            onPressed: onUploadPaymentProof,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload new payment screenshot')),
      if (rental.canCancel) ...[
        const SizedBox(height: 14),
        if (holdEnded)
          OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh rental request')),
        TextButton(onPressed: onCancel, child: const Text('Cancel request')),
      ],
      if (rental.isActive && !rental.hasPendingReturnRequest) ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(
            onPressed: onReturn,
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Request return')),
      ],
    ]));
  }
}
