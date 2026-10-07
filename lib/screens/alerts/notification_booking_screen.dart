import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../models/rental_notification.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import '../admin/rental_admin_view.dart';
import '../shared/transaction_ticket_dialog.dart';
import '../user/return_equipment_screen.dart';

class NotificationBookingScreen extends StatefulWidget {
  const NotificationBookingScreen(
      {super.key,
      required this.notification,
      required this.audience,
      this.api});
  final RentalNotification notification;
  final String audience;
  final MobileApiService? api;
  @override
  State<NotificationBookingScreen> createState() =>
      _NotificationBookingScreenState();
}

class _NotificationBookingScreenState extends State<NotificationBookingScreen> {
  Map<String, dynamic>? _row;
  Map<String, dynamic> _workspace = {};
  String _error = '';
  bool _loading = true;
  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  bool get _admin => widget.audience == 'STAFF';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      Map<String, dynamic> row;
      if (_admin) {
        _workspace = await _api.adminRequest('/workspace');
        final matches = (_workspace['transactions'] as List? ?? [])
            .whereType<Map>()
            .where((row) => row['id'] == widget.notification.rentalId);
        if (matches.isEmpty) {
          throw const MobileApiException('This booking is unavailable.');
        }
        row = Map<String, dynamic>.from(matches.first);
      } else {
        row = await _api.rentalRecord(widget.notification.rentalId);
      }
      if (mounted) {
        setState(() {
          _row = row;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _adminAction(String action) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => RentalAdminActionScreen(
                row: _row!, action: action, workspace: _workspace, api: _api)));
    if (mounted) await _load();
  }

  String _money(dynamic value) =>
      value is num ? '₱${value.toStringAsFixed(2)}' : 'Not recorded';
  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? 'At physical release'
        : DateFormat('MMM d, yyyy h:mm a')
            .format(parsed.toUtc().add(const Duration(hours: 8)));
  }

  @override
  Widget build(BuildContext context) {
    final row = _row, status = row?['status']?.toString() ?? '';
    return Scaffold(
        appBar: AppBar(title: const Text('Booking details'), actions: [
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh booking')
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      RentalNotice(
                          title: widget.notification.title,
                          message: widget.notification.message),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(_error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        OutlinedButton(
                            onPressed: _load, child: const Text('Try again'))
                      ],
                      if (row != null) ...[
                        const SizedBox(height: 20),
                        Text(
                            row['item_name']?.toString() ??
                                widget.notification.rentalCode,
                            style: Theme.of(context).textTheme.headlineSmall),
                        Text(row['rental_code']?.toString() ??
                            widget.notification.rentalCode),
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: RentalStatusBadge(status: status)),
                        const SizedBox(height: 16),
                        if (_admin)
                          RentalValueRow('Customer',
                              row['customer_name']?.toString() ?? 'Customer'),
                        RentalValueRow(
                            'Pickup / resort',
                            row['delivery_location']?.toString() ??
                                'Shop pickup'),
                        RentalValueRow('Rental fee', _money(row['rental_fee'])),
                        RentalValueRow('Refundable deposit',
                            _money(row['deposit_amount'])),
                        RentalValueRow('Return by', _date(row['due_at'])),
                        if (row['balance_due'] != null)
                          RentalValueRow(
                              'Balance due', _money(row['balance_due'])),
                        if (row['refund_due'] != null)
                          RentalValueRow(
                              'Refund due', _money(row['refund_due'])),
                        if ((row['final_reason']?.toString() ?? '').isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(row['final_reason'].toString())),
                        const SizedBox(height: 20),
                        if (_admin &&
                            ['PENDING_ADMIN_APPROVAL', 'PENDING_ESP32_RENT']
                                .contains(status)) ...[
                          FilledButton(
                              onPressed: () => _adminAction('approve'),
                              child: const Text('Review & approve')),
                          OutlinedButton(
                              onPressed: () => _adminAction('reject'),
                              child: const Text('Reject booking')),
                        ],
                        if (_admin && status == 'APPROVED')
                          FilledButton(
                              onPressed: () => _adminAction('release'),
                              child: const Text('Verify & release')),
                        if (_admin && status == 'ACTIVE')
                          FilledButton(
                              onPressed: () => _adminAction('receipt'),
                              child: const Text('Receive returned equipment')),
                        if (_admin && status == 'RETURN_PENDING_INSPECTION')
                          FilledButton(
                              onPressed: () => _adminAction('complete-return'),
                              child: const Text('Inspect & confirm return')),
                        if (!_admin &&
                            ['PENDING_ADMIN_APPROVAL', 'APPROVED']
                                .contains(status))
                          FilledButton.icon(
                              onPressed: () => TransactionTicketDialog.show(
                                  context, RentalModel.fromMap(row)),
                              icon: const Icon(Icons.qr_code),
                              label: const Text('Show transaction QR')),
                        if (!_admin &&
                            status == 'ACTIVE' &&
                            row['latest_return_request_status'] !=
                                'PENDING_ADMIN_APPROVAL')
                          FilledButton(
                              onPressed: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => ReturnEquipmentScreen(
                                            rental: RentalModel.fromMap(row),
                                            api: _api)));
                                if (mounted) _load();
                              },
                              child: const Text('Request return')),
                      ],
                    ])));
  }
}
