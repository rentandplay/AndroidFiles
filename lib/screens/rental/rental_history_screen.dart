import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/mobile_api_service.dart';

class RentalHistoryScreen extends StatefulWidget {
  const RentalHistoryScreen({super.key, this.isAdmin = false});
  final bool isAdmin;
  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  late Future<List<RentalModel>> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RentalModel>> _load() async {
    if (!widget.isAdmin) return MobileApiService.instance.listRentals();
    final result = await MobileApiService.instance.adminRequest('/workspace');
    return (result['transactions'] as List)
        .whereType<Map>()
        .map((row) => RentalModel.fromMap(Map<String, dynamic>.from(row),
            id: row['id'].toString()))
        .toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {}
  }

  String _date(DateTime date) => DateFormat('MMM d, yyyy h:mm a')
      .format(date.toUtc().add(const Duration(hours: 8)));
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.isAdmin ? 'All Transactions' : 'Rental History'),
            actions: [
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))
            ]),
        body: FutureBuilder<List<RentalModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData &&
                  snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              'Could not load rental history. ${snapshot.error}'),
                          TextButton(
                              onPressed: _refresh,
                              child: const Text('Try again'))
                        ])));
              final rentals = snapshot.data ?? [];
              return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (rentals.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(28),
                              child: Text('No rental records yet.')),
                        for (final rental in rentals)
                          Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(rental.itemName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        Text(rental.rentalCode.isNotEmpty
                                            ? rental.rentalCode
                                            : rental.rentalId),
                                        Text(rental.statusLabel),
                                        const Divider(),
                                        if (widget.isAdmin)
                                          Text(
                                              'Customer: ${rental.customerName}'),
                                        Text(rental.isAwaitingPickup ||
                                                rental.isPendingAdminReview
                                            ? 'Timer starts at physical release.'
                                            : 'Started: ${_date(rental.startDate)}'),
                                        if (rental.isActive ||
                                            rental.receivedAt != null ||
                                            rental.returnedDate != null)
                                          Text('Due: ${_date(rental.dueDate)}'),
                                        if (rental.receivedAt != null)
                                          Text(
                                              'Received: ${_date(rental.receivedAt!)}'),
                                        Text(
                                            'Rental fee: ₱${rental.rateFee.toStringAsFixed(2)}'),
                                        Text(
                                            'Refundable deposit: ₱${rental.deposit.toStringAsFixed(2)}'),
                                        Text(
                                            'Payment: ${rental.paymentStatus.replaceAll('_', ' ')}'),
                                        if (rental.balanceDue > 0)
                                          Text(
                                              'Balance due: ₱${rental.balanceDue.toStringAsFixed(2)}'),
                                        if (rental.refundDue > 0)
                                          Text(
                                              'Refund due: ₱${rental.refundDue.toStringAsFixed(2)}'),
                                      ]))),
                      ]));
            }),
      );
}
