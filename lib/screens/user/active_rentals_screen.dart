import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import '../shared/transaction_ticket_dialog.dart';
import 'return_equipment_screen.dart';

class ActiveRentalsScreen extends StatefulWidget {
  const ActiveRentalsScreen({super.key});
  @override
  State<ActiveRentalsScreen> createState() => _ActiveRentalsScreenState();
}

class _ActiveRentalsScreenState extends State<ActiveRentalsScreen> {
  List<RentalModel>? _rentals;
  Timer? _poll;
  bool _refreshing = false;
  String _error = '', _filter = 'All';
  final _cancelling = <String>{};
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

  Future<void> _cancelBooking(RentalModel rental) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Cancel this booking?'),
              content: const Text(
                  'The equipment hold will be released. Any verified payments remain recorded for refund.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep booking')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Cancel booking')),
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
          ? const RentalEmptyState(
              title: 'Sign in to view rentals',
              message: 'Your bookings and equipment in use will appear here.')
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
                              'Follow approval, pickup and return in one place.',
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
                                  label: Text(label),
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
                                ? 'Choose equipment from the catalog to start a booking.'
                                : 'Try another filter to see your other rentals.',
                            action: open.isNotEmpty
                                ? TextButton(
                                    onPressed: () =>
                                        setState(() => _filter = 'All'),
                                    child: const Text('Show all rentals'))
                                : null,
                          ),
                        for (final rental in visible)
                          RentalBookingCard(
                            rental: rental,
                            onTicket: () =>
                                TransactionTicketDialog.show(context, rental),
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
      this.onRefresh});
  final RentalModel rental;
  final VoidCallback? onTicket, onCancel, onReturn, onRefresh;
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
            'Refresh to check the latest status before making another booking.'
          )
        : rental.isPendingAdminReview
            ? (
                'Waiting for admin approval',
                'Your booking is being reviewed. The rental clock has not started.'
              )
            : rental.isAwaitingPickup
                ? (
                    'Ready to receive your equipment',
                    'Show your booking QR and valid ID to the admin. Pay and check the item at handoff.'
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
      if (rental.holdExpiresAt != null && rental.canCancel)
        RentalValueRow(
            rental.isPendingAdminReview ? 'Review hold ends' : 'Pickup before',
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
      if (rental.canCancel) ...[
        const SizedBox(height: 14),
        if (holdEnded)
          OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh booking'))
        else
          FilledButton.icon(
              onPressed: onTicket,
              icon: const Icon(Icons.qr_code),
              label: const Text('Show booking QR')),
        TextButton(onPressed: onCancel, child: const Text('Cancel booking')),
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
