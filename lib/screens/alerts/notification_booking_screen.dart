import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../models/rental_notification.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rental_ui.dart';
import '../admin/rental_admin_view.dart';
import '../admin/rental_extra_screen.dart';
import '../shared/transaction_ticket_dialog.dart';
import '../user/return_equipment_screen.dart';
import '../../widgets/rental_dual_tracker.dart';
import '../../widgets/notification_widgets.dart';

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
  StreamSubscription<Map<String, dynamic>>? _events;
  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  bool get _admin => widget.audience == 'STAFF';
  @override
  void initState() {
    super.initState();
    RentalNotificationSuppression.activeRentalId =
        widget.notification.rentalId.isNotEmpty
            ? widget.notification.rentalId
            : widget.notification.rentalCode;
    _events = _api.watchRentalEvents().listen((event) {
      final id = event['rentalId']?.toString();
      final targetId = widget.notification.rentalId.isNotEmpty
          ? widget.notification.rentalId
          : widget.notification.rentalCode;
      if (event['event'] == 'ready' ||
          (event['event'] == 'rental.changed' &&
              (id == null || id.isEmpty || id == targetId))) {
        if (mounted) _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _events?.cancel();
    RentalNotificationSuppression.activeRentalId = null;
    super.dispose();
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
            .where((row) => row['id']?.toString() == widget.notification.rentalId);
        if (matches.isEmpty) {
          throw const MobileApiException('This rental request is unavailable.');
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
  int _progressStep(RentalModel rental) {
    if (rental.normalizedStatus == 'COMPLETED' || rental.isAwaitingInspection) return 3;
    if (rental.isActive || rental.hasPendingReturnRequest) return 2;
    if (rental.isPendingVerification) {
      return rental.normalizedStatus.contains('RETURN') ? 3 : 1;
    }
    if (rental.isAwaitingPickup) return 1;
    return 0;
  }
  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? 'At handoff'
        : DateFormat('MMM d, yyyy h:mm a')
            .format(parsed.toUtc().add(const Duration(hours: 8)));
  }

  @override
  Widget build(BuildContext context) {
    final row = _row, status = row?['status']?.toString() ?? '';
    return Scaffold(
        appBar: GlassAppBar(titleText: 'Rental details', actions: [
          HeaderActionPod(
              onTap: _load,
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh rental')
        ]),
        body: LiquidAmbientBackdrop(
          child: _loading
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
                          if (!_admin) ...[
                            Builder(builder: (context) {
                              final rentalObj = RentalModel.fromMap(row);
                              final isOngoing = rentalObj.isActive ||
                                  rentalObj.isPendingVerification ||
                                  rentalObj.isAwaitingPickup ||
                                  rentalObj.isAwaitingInspection ||
                                  rentalObj.hasPendingReturnRequest ||
                                  rentalObj.normalizedStatus == 'COMPLETED';
                              if (!isOngoing) return const SizedBox.shrink();
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 14),
                                  RentalDualTracker(
                                      rental: rentalObj,
                                      step: _progressStep(rentalObj),
                                      initiallyExpanded: true),
                                  if (rentalObj.isAwaitingPickup) ...[
                                    const SizedBox(height: 6),
                                    EmbeddedRentalHandoffQr(
                                        rental: rentalObj, api: _api),
                                  ],
                                ],
                              );
                            }),
                          ],
                          const SizedBox(height: 16),
                          if (_admin)
                            RentalValueRow('Customer',
                                row['customer_name']?.toString() ?? 'Customer'),
                          RentalValueRow(
                              'Pickup / resort',
                              row['delivery_location']?.toString() ??
                                  'Shop pickup'),
                          RentalValueRow(
                              'Rental fee', _money(row['rental_fee'])),
                          if (!['REJECTED', 'CANCELLED']
                                  .contains(status.toUpperCase()) ||
                              DateTime.tryParse(
                                      row['due_at']?.toString() ?? '') !=
                                  null)
                            RentalValueRow('Return by', _date(row['due_at'])),
                          if (DateTime.tryParse(
                                  row['returned_at']?.toString() ?? '') !=
                              null)
                            RentalValueRow(
                                'Returned', _date(row['returned_at'])),
                          if (row['balance_due'] != null)
                            RentalValueRow(
                                'Balance due', _money(row['balance_due'])),
                          if (row['refund_due'] != null)
                            RentalValueRow(
                                'Refund due', _money(row['refund_due'])),
                          if ((row['final_reason']?.toString() ?? '').isNotEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(row['final_reason'].toString())),
                          const SizedBox(height: 20),
                          if (_admin &&
                              ['PENDING_ADMIN_APPROVAL', 'PENDING_ESP32_RENT']
                                  .contains(status)) ...[
                            if (row['payment_method'] != 'QR')
                              FilledButton(
                                  onPressed: () => _adminAction('approve'),
                                  child: const Text('Approve rental request'))
                            else if (row['payment_proof_status'] ==
                                'PENDING_REVIEW')
                              FilledButton(
                                  onPressed: () =>
                                      _adminAction('payment-review'),
                                  child:
                                      const Text('Review payment screenshot'))
                            else
                              const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text(
                                      'Waiting for a corrected payment screenshot')),
                            OutlinedButton(
                                onPressed: () => _adminAction('reject'),
                                child: const Text('Reject rental request')),
                          ],
                          if (_admin && status == 'APPROVED')
                            FilledButton(
                                onPressed: () => _adminAction(
                                    row['delivery_status'] == 'PREPARED'
                                        ? 'release'
                                        : 'prepare-delivery'),
                                child: Text(row['delivery_status'] == 'PREPARED'
                                    ? 'Confirm resort handoff'
                                    : 'Prepare for delivery')),
                          if (_admin && status == 'ACTIVE')
                            FilledButton(
                                onPressed: () => _adminAction('receipt'),
                                child: const Text('Receive returned equipment')),
                          if (row['extension_request'] is Map &&
                              (row['extension_request']['status']?.toString() ??
                                      '')
                                  .isNotEmpty) ...[
                            Builder(builder: (context) {
                              final ext = Map<String, dynamic>.from(
                                  row['extension_request'] as Map);
                              final quote = ext['quote'] is Map
                                  ? ext['quote'] as Map
                                  : const {};
                              final mins = (quote['billed_minutes'] as num?)
                                      ?.round() ??
                                  (ext['additional_minutes'] as num?)?.round() ??
                                  0;
                              final extStatus =
                                  (ext['status']?.toString() ?? '')
                                      .toUpperCase();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RentalValueRow(
                                      'Extension status',
                                      extStatus == 'PENDING'
                                          ? 'Pending review (+${mins}m)'
                                          : extStatus == 'APPROVED'
                                              ? 'Approved (+${mins}m)'
                                              : 'Declined',
                                    ),
                                    if (ext['requested_due_at'] != null)
                                      RentalValueRow(
                                        extStatus == 'APPROVED'
                                            ? 'Extended due time'
                                            : 'Requested due time',
                                        _date(ext['requested_due_at']),
                                      ),
                                    if (ext['additional_fee'] != null)
                                      RentalValueRow('Extension charge',
                                          _money(ext['additional_fee'])),
                                    if ((ext['reason']?.toString() ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      RentalValueRow('Extension note',
                                          ext['reason'].toString().trim()),
                                  ],
                                ),
                              );
                            }),
                          ],
                          if (_admin &&
                              status == 'ACTIVE' &&
                              row['extension_request'] is Map &&
                              (row['extension_request']['status']?.toString() ??
                                      '')
                                  .toUpperCase() ==
                                  'PENDING') ...[
                            const SizedBox(height: 10),
                            FilledButton.icon(
                                onPressed: () async {
                                  final changed = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => RentalExtraScreen(
                                              api: _api,
                                              kind: 'extension-review',
                                              row: row)));
                                  if (changed == true && mounted) await _load();
                                },
                                icon: const Icon(Icons.more_time_rounded),
                                label: const Text('Review extension')),
                          ],
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
                                icon: Icon(status == 'APPROVED'
                                    ? Icons.qr_code_rounded
                                    : Icons.confirmation_number_outlined),
                                label: Text(status == 'APPROVED'
                                    ? 'Show rental handoff QR'
                                    : 'View booking request hold')),
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
                          if (!_admin &&
                              (row['latest_return_request_status'] ==
                                      'PENDING_ADMIN_APPROVAL' ||
                                  RentalModel.fromMap(row)
                                      .isReturnAwaitingTerminalConfirmation ||
                                  status == 'RETURN_PENDING_INSPECTION' ||
                                  status == 'COMPLETED'))
                            FilledButton.icon(
                                onPressed: () async {
                                  await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              RentalReturnStatusScreen(
                                                  rental:
                                                      RentalModel.fromMap(row),
                                                  api: _api)));
                                  if (mounted) _load();
                                },
                                icon: const Icon(
                                    Icons.assignment_return_outlined),
                                label: Text(status == 'COMPLETED'
                                    ? 'View return confirmation & status'
                                    : 'View return status & progress')),
                        ],
                      ])),
        ));
  }
}
