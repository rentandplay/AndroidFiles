import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/rental_model.dart';
import '../../services/mobile_api_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<RentalModel> _rentals = [];
  Timer? _clock, _refresh;
  bool _loading = true, _fetching = false;
  String _error = '';
  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  Future<void> _load() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final rentals = await MobileApiService.instance.listRentals();
      if (mounted)
        setState(() {
          _rentals = rentals;
          _loading = false;
          _error = '';
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    } finally {
      _fetching = false;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  Widget _rentalCard(RentalModel rental) {
    final left = rental.dueDate.difference(DateTime.now());
    final overdue = rental.isActive && left.isNegative;
    String message = rental.statusLabel;
    if (rental.isActive) {
      final duration = left.abs();
      final time =
          '${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
      message =
          '${overdue ? 'Overdue by' : 'Time remaining'} $time. Return the equipment to the admin.';
    } else if (rental.isAwaitingPickup) {
      message =
          'Approved. Show your transaction QR at pickup. The timer starts at physical release.';
    } else if (rental.isPendingAdminReview) {
      message =
          'Waiting for admin approval. Your booking hold has a limited duration.';
    } else if (rental.isAwaitingInspection) {
      message =
          'The admin received your equipment. The rental timer has stopped; inspection is pending.';
    }
    if (rental.balanceDue > 0 && !rental.canCancel)
      message += '\nBalance due: ₱${rental.balanceDue.toStringAsFixed(2)}';
    if (rental.refundDue > 0)
      message += '\nRefund pending: ₱${rental.refundDue.toStringAsFixed(2)}';
    return Card(
        child: ListTile(
            leading: Icon(overdue ? Icons.timer_off : Icons.receipt_long,
                color: overdue ? Colors.red : null),
            title: Text(rental.itemName),
            subtitle: Text(message),
            isThreeLine: true));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Alerts & Rental Timers'), actions: [
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh')
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (_error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(_error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_rentals.isEmpty) const Text('No rental updates yet.'),
                  for (final rental in _rentals.where((rental) =>
                      rental.isOpen ||
                      rental.balanceDue > 0 ||
                      rental.refundDue > 0))
                    _rentalCard(rental),
                  const SizedBox(height: 12),
                  const Text(
                      'Statuses refresh automatically. The admin records release and receipt times.'),
                ])),
      );
}
