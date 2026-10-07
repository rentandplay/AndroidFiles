import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/mobile_api_service.dart';
import '../../services/release_verification.dart';
import '../../widgets/rental_ui.dart';
import '../shared/qr_capture_screen.dart';

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> _rows(dynamic value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];
String _text(dynamic value) => value?.toString() ?? '';
double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;
String _money(dynamic value) =>
    value == null ? 'Not recorded' : '₱${_number(value).toStringAsFixed(2)}';
String _date(dynamic value) {
  final raw = _text(value);
  final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(raw)
      ? raw
      : raw.replaceFirst(' ', 'T') + '+08:00';
  final date = DateTime.tryParse(zoned);
  return date == null
      ? 'Set at physical release'
      : DateFormat('MMM d, yyyy h:mm a')
          .format(date.toUtc().add(const Duration(hours: 8)));
}

class RentalAdminView extends StatefulWidget {
  const RentalAdminView(
      {super.key,
      required this.page,
      required this.workspace,
      required this.onChanged,
      this.initialScanKind,
      this.scanRequestId = 0,
      this.onScanConsumed});
  final String page;
  final Map<String, dynamic> workspace;
  final Future<void> Function() onChanged;
  final String? initialScanKind;
  final int scanRequestId;
  final VoidCallback? onScanConsumed;
  @override
  State<RentalAdminView> createState() => _RentalAdminViewState();
}

class _RentalAdminViewState extends State<RentalAdminView> {
  String _query = '', _stage = 'All';
  final _api = MobileApiService.instance;

  @override
  void initState() {
    super.initState();
    _scheduleRequestedScan();
  }

  @override
  void didUpdateWidget(covariant RentalAdminView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scanRequestId != oldWidget.scanRequestId) {
      _scheduleRequestedScan();
    }
  }

  void _scheduleRequestedScan() {
    final kind = widget.initialScanKind;
    if (kind == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onScanConsumed?.call();
      unawaited(_lookup(kind));
    });
  }

  Future<void> _action(Map<String, dynamic> row, String action,
      {String? code}) async {
    await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => RentalAdminActionScreen(
                row: row,
                action: action,
                workspace: widget.workspace,
                scannedCode: code)));
    await widget.onChanged();
  }

  Future<void> _lookup(String kind) async {
    final code = await Navigator.push<String>(
        context,
        MaterialPageRoute(
            builder: (_) => QrCaptureScreen(
                title: kind == 'BOOKING'
                    ? 'Scan rental QR'
                    : 'Scan inventory QR')));
    if (code == null || !mounted) return;
    try {
      final result = await _api.adminRequest('/rentals/lookup',
          method: 'POST', body: {'kind': kind, 'code': code});
      if (!mounted) return;
      final row = _map(result['rental']);
      if (kind == 'INVENTORY') {
        if (row['status'] == 'RETURN_PENDING_INSPECTION') {
          await _action(row, 'complete-return', code: code);
        } else if (row['status'] == 'ACTIVE') {
          await _action(row, 'receipt', code: code);
        } else if (row['status'] == 'APPROVED' &&
            row['delivery_status'] != 'PREPARED') {
          await _action(row, 'prepare-delivery', code: code);
        } else {
          _details(row);
        }
      } else if (row['status'] == 'APPROVED' &&
          row['delivery_status'] == 'PREPARED') {
        await _action(row, 'release', code: code);
      } else {
        _details(row, code: code);
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _manualLookup() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Find rental or returned item'),
                content: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                        labelText: widget.page == 'Returns'
                            ? 'Inventory code'
                            : 'Rental code')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, controller.text.trim()),
                      child: const Text('Find'))
                ]));
    controller.dispose();
    if (code == null || code.isEmpty) return;
    try {
      final result = await _api.adminRequest('/rentals/lookup',
          method: 'POST',
          body: {
            'kind': widget.page == 'Returns' ? 'INVENTORY' : 'BOOKING',
            'code': code
          });
      if (mounted) _details(_map(result['rental']));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  void _details(Map<String, dynamic> row, {String? code}) {
    final fee = _map(row['fee_breakdown']);
    void open(String action) {
      Navigator.pop(context);
      _action(row, action, code: action == 'release' ? code : null);
    }

    showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(_text(row['item_name'])),
                content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(
                              '${row['customer_name']} · ${row['item_code'] ?? ''}'),
                          Text(_text(row['rental_code'] ?? row['id'])),
                          const Divider(),
                          RentalStatusBadge(status: _text(row['status'])),
                          const SizedBox(height: 12),
                          if (['APPROVED', 'PENDING_ADMIN_APPROVAL']
                              .contains(row['status']))
                            RentalValueRow(
                                'Hold ends', _date(row['hold_expires_at'])),
                          Text(
                              'Released: ${_date(row['confirmed_rental_at'])}'),
                          if (row['due_at'] != null)
                            RentalValueRow('Return by', _date(row['due_at'])),
                          if (row['received_at'] != null)
                            Text(
                                'Physically received: ${_date(row['received_at'])}'),
                          const Divider(height: 24),
                          RentalValueRow(
                              'Rental fee', _money(row['rental_fee'])),
                          RentalValueRow('Refundable deposit',
                              _money(row['deposit_amount'])),
                          if (fee['overtime_fee'] != null)
                            RentalValueRow(
                                'Overtime', _money(fee['overtime_fee'])),
                          if (fee['penalty_amount'] != null)
                            RentalValueRow('Damage / missing parts',
                                _money(fee['penalty_amount'])),
                          if (fee['final_rental_charges'] != null)
                            Text(
                                'Final rental charges: ${_money(fee['final_rental_charges'])}'),
                          RentalValueRow(
                              'Balance due', _money(row['balance_due'])),
                          if (['COMPLETED', 'CANCELLED', 'REJECTED', 'EXPIRED']
                              .contains(row['status']))
                            RentalValueRow(
                                'Refund due', _money(row['refund_due'])),
                          if (row['final_reason'] != null)
                            Text(_text(row['final_reason'])),
                          for (final phase in [
                            'release_condition',
                            'return_condition'
                          ])
                            if (row[phase] is Map) ...[
                              const Divider(),
                              Text(
                                  phase == 'release_condition'
                                      ? 'Release inspection'
                                      : 'Return inspection',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(_text(_map(row[phase])['condition'])),
                              Text(_text(_map(row[phase])['notes'])),
                              for (final id
                                  in (_map(row[phase])['photo_ids'] as List? ??
                                      []))
                                TextButton(
                                    onPressed: () => _photo(_text(id)),
                                    child: const Text('View inspection photo'))
                            ],
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Close')),
                          if (row['status'] == 'PENDING_ADMIN_APPROVAL') ...[
                    TextButton(
                        onPressed: () => open('reject'),
                                child: const Text('Reject request')),
                            if (row['payment_method'] != 'QR')
                              FilledButton(
                                  onPressed: () => open('approve'),
                                  child: const Text('Approve rental request'))
                            else if (row['payment_proof_status'] ==
                                'PENDING_REVIEW') ...[
                              TextButton(
                                  onPressed: () => open('payment-reject'),
                                  child: const Text('Reject payment proof')),
                              FilledButton(
                                  onPressed: () => open('payment-review'),
                                  child: const Text('Review payment screenshot'))
                            ] else
                              const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('Waiting for payment screenshot')),
                  ],
                  if (row['status'] == 'APPROVED') ...[
                    TextButton(
                        onPressed: () => open('assignment'),
                        child: const Text('Change unit')),
                    TextButton(
                        onPressed: () => open('reject'),
                                child: const Text('Cancel request')),
                    FilledButton(
                                onPressed: () => open(
                                    row['delivery_status'] == 'PREPARED'
                                        ? 'release'
                                        : 'prepare-delivery'),
                                child: Text(row['delivery_status'] == 'PREPARED'
                                    ? 'Confirm resort handoff'
                                    : 'Prepare for delivery'))
                  ],
                  if (row['status'] == 'ACTIVE')
                    FilledButton(
                        onPressed: () => open('receipt'),
                        child: const Text('Record physical receipt')),
                  if (row['status'] == 'RETURN_PENDING_INSPECTION')
                    FilledButton(
                        onPressed: () => open('complete-return'),
                        child: const Text('Complete inspection')),
                  if (['COMPLETED', 'CANCELLED', 'REJECTED', 'EXPIRED']
                          .contains(row['status']) &&
                      row.containsKey('rental_paid_amount'))
                    TextButton(
                        onPressed: () => open('settlement'),
                        child: const Text('Payment / refund')),
                ]));
  }

  String? _nextAction(Map<String, dynamic> row) => switch (row['status']) {
        'PENDING_ADMIN_APPROVAL' => row['payment_method'] == 'QR'
            ? (row['payment_proof_status'] == 'PENDING_REVIEW'
                ? 'payment-review'
                : null)
            : 'approve',
        'APPROVED' => row['delivery_status'] == 'PREPARED'
            ? 'release'
            : 'prepare-delivery',
        'ACTIVE' => 'receipt',
        'RETURN_PENDING_INSPECTION' => 'complete-return',
        _ => null,
      };
  String _nextLabel(Map<String, dynamic> row) => switch (_nextAction(row)) {
        'payment-review' => 'Review payment screenshot',
        'approve' => 'Approve rental request',
        'prepare-delivery' => 'Prepare for delivery',
        'release' => 'Confirm resort handoff',
        'receipt' => 'Receive equipment',
        'complete-return' => 'Complete inspection',
        _ => 'View details',
      };

  Future<void> _photo(String id) async {
    try {
      final result = await _api
          .adminRequest('/rental-inspection-photos/${Uri.encodeComponent(id)}');
      if (!mounted) return;
      final data = _text(_map(result['photo'])['data_url']);
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  content: Image.memory(base64Decode(data.split(',').last)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close'))
                  ]));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _rows(widget.workspace['transactions']);
    final filtered = all.where((row) {
      final status = row['status'];
      final relevant = widget.page == 'Rentals'
          ? [
              'PENDING_ADMIN_APPROVAL',
              'APPROVED',
              'ACTIVE',
              'RETURN_PENDING_INSPECTION',
              'PENDING_VERIFICATION'
            ].contains(status)
          : widget.page == 'Returns'
              ? ['ACTIVE', 'RETURN_PENDING_INSPECTION', 'COMPLETED']
                  .contains(status)
              : true;
      return relevant &&
          (_stage == 'All' || _stage == rentalStatusLabel(_text(status))) &&
          [
            row['rental_code'],
            row['item_name'],
            row['customer_name'],
            row['item_code'],
            status
          ].join(' ').toLowerCase().contains(_query.toLowerCase());
    }).toList();
    return RefreshIndicator(
        onRefresh: widget.onChanged,
        child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(widget.page,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const RentalNotice(
                  message:
                      'Review the payment, scan the equipment QR at the shop to prepare it, then scan the customer rental QR at the resort when the item is handed over. The rental timer starts at handoff.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (widget.page == 'Rentals')
                  FilledButton.icon(
                      onPressed: () => _action({}, 'booking'),
                      icon: const Icon(Icons.add),
                      label: const Text('Create counter rental')),
                if (widget.page != 'Transaction History')
                  OutlinedButton.icon(
                      onPressed: () => _lookup(
                          widget.page == 'Returns' ? 'INVENTORY' : 'BOOKING'),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(widget.page == 'Returns'
                          ? 'Scan equipment QR'
                          : 'Scan rental QR')),
                OutlinedButton(
                    onPressed: _manualLookup,
                    child: const Text('Find by code')),
              ]),
              const SizedBox(height: 12),
              TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                      labelText: 'Search equipment, customer or rental',
                      prefixIcon: Icon(Icons.search))),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final stage in [
                  'All',
                  ...all
                      .map((row) => rentalStatusLabel(_text(row['status'])))
                      .toSet()
                ])
                  ChoiceChip(
                      label: Text(stage),
                      selected: _stage == stage,
                      onSelected: (_) => setState(() => _stage = stage)),
              ]),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const RentalEmptyState(
                    title: 'No matching rentals',
                    message:
                        'Try another stage or search by rental, customer or equipment.'),
              for (final row in filtered)
                RentalSection(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Row(children: [
                        Expanded(
                            child: Text(_text(row['item_name']),
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))),
                        IconButton(
                            tooltip: 'View rental details',
                            onPressed: () => _details(row),
                            icon: const Icon(Icons.more_horiz)),
                      ]),
                      Text(_text(row['customer_name'])),
                      const SizedBox(height: 6),
                      Text(
                          '${row['rental_code'] ?? row['id']} · ${row['item_code'] ?? ''}',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12)),
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerLeft,
                          child:
                              RentalStatusBadge(status: _text(row['status']))),
                      const SizedBox(height: 12),
                      if (row['status'] == 'ACTIVE')
                        RentalValueRow('Return by', _date(row['due_at'])),
                      if (['APPROVED', 'PENDING_ADMIN_APPROVAL']
                          .contains(row['status']))
                        RentalValueRow(
                            'Hold ends', _date(row['hold_expires_at'])),
                      if (row['status'] == 'RETURN_PENDING_INSPECTION')
                        RentalValueRow(
                            'Physically received', _date(row['received_at'])),
                      if (row['balance_due'] != null)
                        RentalValueRow('Balance', _money(row['balance_due'])),
                      const SizedBox(height: 10),
                      if (_nextAction(row) != null)
                        FilledButton(
                            onPressed: () => _action(row, _nextAction(row)!),
                            child: Text(_nextLabel(row)))
                      else
                        OutlinedButton(
                            onPressed: () => _details(row),
                            child: const Text('View details')),
                    ])),
            ]));
  }
}

class RentalAdminActionScreen extends StatefulWidget {
  const RentalAdminActionScreen(
      {super.key,
      required this.row,
      required this.action,
      required this.workspace,
      this.scannedCode,
      this.api});
  final Map<String, dynamic> row, workspace;
  final String action;
  final String? scannedCode;
  final MobileApiService? api;
  @override
  State<RentalAdminActionScreen> createState() =>
      _RentalAdminActionScreenState();
}

class _RentalAdminActionScreenState extends State<RentalAdminActionScreen> {
  final _form = GlobalKey<FormState>();
  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  late ReleaseVerification _verification;
  bool _previewing = false;
  int _quoteVersion = 0;
  final _transaction = TextEditingController(),
      _inventory = TextEditingController(),
      _reason = TextEditingController(),
      _notes = TextEditingController(),
      _minutes = TextEditingController(text: '60'),
      _location = TextEditingController(text: 'Shop pickup');
  final _penalty = TextEditingController(text: '0'),
      _payment = TextEditingController(text: '0'),
      _applied = TextEditingController(text: '0'),
      _refund = TextEditingController(text: '0'),
      _rentalRefund = TextEditingController(text: '0');
  late Map<String, dynamic> _row;
  late String _action;
  late String _key;
  String _condition = 'GOOD',
      _result = 'AVAILABLE',
      _method = 'CASH',
      _error = '';
  String? _itemId, _customerId;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _paymentProof;
  bool _paymentProofLoading = false;
  bool _manual = false,
      _customerVerified = false,
      _paymentVerified = false,
      _depositReceived = false,
      _accessories = false,
      _receipt = false,
      _busy = false,
      _changed = false;
  final List<String> _photos = [];
  @override
  void initState() {
    super.initState();
    _row = {...widget.row};
    _action = widget.action;
    _key = MobileApiService.operationKey();
    _verification = ReleaseVerification(
        rentalId: _text(_row['id']),
        request: (payload) => _api.adminRequest(
            '/rentals/${Uri.encodeComponent(_text(_row['id']))}/release-verification',
            method: 'POST',
            body: payload));
    _verification.addListener(_verificationChanged);
    _transaction.addListener(() {
      if (_action == 'release')
        _verification.updateTransaction(_transaction.text);
    });
    _inventory.addListener(() {
      if (_action == 'release') _verification.updateInventory(_inventory.text);
    });
    _reason.addListener(() {
      if (_action == 'release') _verification.updateReason(_reason.text);
    });
    _penalty.addListener(() {
      if (mounted) setState(() {});
    });
    _minutes.addListener(() {
      _quoteVersion++;
      if (mounted)
        setState(() {
          _quote = null;
          _previewing = false;
        });
    });
    if (_action == 'release') _transaction.text = widget.scannedCode ?? '';
    if (_action == 'receipt') _inventory.text = widget.scannedCode ?? '';
    if (_action == 'prepare-delivery')
      _inventory.text = widget.scannedCode ?? '';
    if (_action == 'payment-review') _loadPaymentProof();
    _paymentVerified =
        _number(_row['rental_paid_amount']) >= _number(_row['rental_fee']) &&
            _row.containsKey('rental_paid_amount');
    _depositReceived = _number(_row['deposit_collected_amount']) >=
        _number(_row['deposit_amount']);
  }

  Future<void> _loadPaymentProof() async {
    setState(() => _paymentProofLoading = true);
    try {
      final result = await _api.adminRequest(
          '/rentals/${Uri.encodeComponent(_text(_row['id']))}/payment-proof');
      if (mounted) setState(() => _paymentProof = _map(result['proof']));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _paymentProofLoading = false);
    }
  }

  @override
  void dispose() {
    _quoteVersion++;
    _verification.removeListener(_verificationChanged);
    _verification.dispose();
    for (final controller in [
      _transaction,
      _inventory,
      _reason,
      _notes,
      _minutes,
      _location,
      _penalty,
      _payment,
      _applied,
      _refund,
      _rentalRefund
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _scan(TextEditingController target, String title) async {
    final value = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => QrCaptureScreen(title: title)));
    if (value != null && mounted) {
      target.text = value;
      if (_action == 'release' && !_manual) await _verification.verify();
    }
  }

  Widget _field(TextEditingController controller, String label,
          {bool required = true, bool numeric = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextFormField(
              controller: controller,
              enabled: !_busy && !_verification.busy && !_previewing,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              minLines: controller == _notes ? 2 : 1,
              maxLines: controller == _notes ? 3 : 1,
              decoration: InputDecoration(labelText: label),
              validator: (value) {
                if (required && (value?.trim().isEmpty ?? true))
                  return 'This field is required';
                if (controller == _minutes &&
                    (int.tryParse(value ?? '') == null ||
                        int.parse(value!) <= 0))
                  return 'Enter a positive whole number of minutes';
                if (numeric &&
                    (double.tryParse(value ?? '') == null ||
                        double.parse(value!) < 0))
                  return 'Enter a nonnegative amount';
                return null;
              }));
  Widget _check(String label, bool value, ValueChanged<bool> change) =>
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: _busy || _verification.busy
              ? null
              : (value) => setState(() => change(value ?? false)));
  Widget _qr(TextEditingController controller, String label) =>
      Column(children: [
        _field(controller, label),
        OutlinedButton.icon(
            onPressed: _busy || _verification.busy
                ? null
                : () => _scan(controller, label),
            icon: const Icon(Icons.qr_code_scanner),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            label: const Text('Scan with camera'))
      ]);
  void _verificationChanged() {
    if (mounted) setState(() {});
  }

  Widget _manualControl() => Column(children: [
        _check('Enter printed codes instead', _manual, (value) {
          _manual = value;
          _transaction.clear();
          _inventory.clear();
          _verification.updateManual(value);
        }),
        if (_manual) ...[
          const Text('Use the printed codes when the QR cannot be scanned.'),
          _field(_reason, 'Reason for using printed codes'),
        ],
      ]);
  List<Widget> _releaseFields() => [
        RentalSteps(
            step: _verification.step == 2 ? 1 : 0,
            labels: const ['Customer rental QR', 'Physical handoff']),
        if (_verification.step == 0)
          RentalSection(
              title: 'Verify the customer rental',
              icon: Icons.qr_code,
              subtitle:
                  'At the delivery location, scan the rental QR shown in My Rentals. Equipment was already checked at the shop.',
              child: Column(children: [
                _qr(
                    _transaction,
                    _manual
                        ? 'Printed rental code'
                        : 'Customer rental QR'),
                _manualControl()
              ])),
        if (_verification.step == 2) ...[
          const RentalNotice(
              title: 'Rental and prepared unit verified',
              icon: Icons.check_circle_outline,
              message:
                  'The operator prepared this unit at the shop. At the selected location, confirm the customer, payment and physical handoff.'),
          const SizedBox(height: 16),
          RentalSection(
              title: 'Confirm the handoff',
              child: Column(children: [
                _check('The receiver matches the rental customer.',
                    _customerVerified, (value) => _customerVerified = value),
                const Divider(height: 20),
                RentalValueRow('Rental fee', _money(_row['rental_fee'])),
                _check('Rental payment received and verified', _paymentVerified,
                    (value) => _paymentVerified = value),
                RentalValueRow(
                    'Refundable deposit', _money(_row['deposit_amount'])),
                _check('Required refundable deposit received', _depositReceived,
                    (value) => _depositReceived = value),
              ])),
          RentalSection(
              title: 'Equipment inspection',
              subtitle: 'Record its condition before handoff.',
              child: _inspection(true)),
        ],
      ];
  Future<void> _addPhoto(ImageSource source) async {
    try {
      if (_photos.length >= 2) throw Exception('Attach at most two photos.');
      final file = await ImagePicker().pickImage(
          source: source, maxWidth: 640, maxHeight: 640, imageQuality: 55);
      if (file == null) return;
      final data =
          'data:image/jpeg;base64,${base64Encode(await file.readAsBytes())}';
      if (data.length > 150000) throw Exception('Choose a smaller photo.');
      if (mounted) setState(() => _photos.add(data));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Widget _inspection(bool release) => Column(children: [
        DropdownButtonFormField<String>(
            initialValue: _condition,
            decoration: const InputDecoration(labelText: 'Condition'),
            items: [
              for (final value in release
                  ? ['GOOD', 'FAIR']
                  : ['GOOD', 'FAIR', 'DAMAGED', 'NEEDS_INSPECTION'])
                DropdownMenuItem(
                    value: value, child: Text(value.replaceAll('_', ' ')))
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                      _condition = value!;
                      if (['DAMAGED', 'NEEDS_INSPECTION'].contains(value))
                        _result = 'UNDER_MAINTENANCE';
                    })),
        if (!release)
          DropdownButtonFormField<String>(
              key: ValueKey('result_$_condition'),
              initialValue: _result,
              decoration:
                  const InputDecoration(labelText: 'Next equipment status'),
              items: [
                if (!['DAMAGED', 'NEEDS_INSPECTION'].contains(_condition))
                  const DropdownMenuItem(
                      value: 'AVAILABLE', child: Text('Available')),
                const DropdownMenuItem(
                    value: 'UNDER_MAINTENANCE',
                    child: Text('Under maintenance / inspection'))
              ],
              onChanged:
                  _busy ? null : (value) => setState(() => _result = value!)),
        _check('I checked this unit and all included accessories.',
            _accessories, (value) => _accessories = value),
        _field(_notes, 'Inspection notes'),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _addPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Optional photo')),
          TextButton(
              onPressed: _busy ? null : () => _addPhoto(ImageSource.gallery),
              child: const Text('Choose photo'))
        ]),
        Wrap(spacing: 8, children: [
          for (var index = 0; index < _photos.length; index++)
            Column(children: [
              Image.memory(base64Decode(_photos[index].split(',').last),
                  width: 100, height: 85, fit: BoxFit.cover),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _photos.removeAt(index)),
                  child: const Text('Remove'))
            ])
        ])
      ]);
  Map<String, dynamic> _inspectionPayload() => {
        'condition': _condition,
        'result': _action == 'release' ? 'AVAILABLE' : _result,
        'notes': _notes.text.trim(),
        'accessoriesChecked': _accessories,
        'photos': _photos
      };
  Map<String, dynamic> _bookingPayload() => {
        'itemId': _itemId,
        'customerId': _customerId,
        'durationMinutes': int.parse(_minutes.text),
        'mode': 'TIMED',
        'deliveryLocation': _location.text.trim(),
        'paymentMethod': _method
      };
  Future<void> _preview() async {
    if (!_form.currentState!.validate() || _previewing) return;
    final version = ++_quoteVersion;
    setState(() {
      _previewing = true;
      _error = '';
      _quote = null;
    });
    try {
      final result = await _api.adminRequest('/pricing/quote',
          method: 'POST', body: _bookingPayload());
      if (mounted && version == _quoteVersion)
        setState(() => _quote = _map(result['quote']));
    } catch (error) {
      if (mounted && version == _quoteVersion)
        setState(() => _error = '$error');
    } finally {
      if (mounted && version == _quoteVersion)
        setState(() => _previewing = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (['release', 'complete-return'].contains(_action) && !_accessories) {
      setState(() => _error = 'Check the unit and included accessories first.');
      return;
    }
    if (_action == 'release' &&
        (!_verification.bookingVerified || _verification.step != 2)) {
      setState(() => _error = 'Verify the customer rental QR before handoff.');
      return;
    }
    if (_action == 'release' && !_customerVerified) {
      setState(() => _error = 'Verify the customer receiving the equipment.');
      return;
    }
    if (_action == 'prepare-delivery' &&
        (_inventory.text.trim().isEmpty || _manual && _reason.text.trim().isEmpty)) {
      setState(() => _error = _manual
          ? 'Enter the equipment code and reason for manual verification.'
          : 'Scan the assigned equipment QR at the shop.');
      return;
    }
    if (_action == 'payment-review' && !_paymentVerified) {
      setState(() => _error =
          'Confirm that the screenshot shows a successful transfer for the exact total.');
      return;
    }
    if (_action == 'payment-reject' && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter why the payment screenshot is being rejected.');
      return;
    }
    if (_action == 'receipt' && !_receipt) {
      setState(() => _error =
          'Confirm that the equipment is physically back at the desk.');
      return;
    }
    if (_action == 'booking' && _quote == null) {
      await _preview();
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(_title),
                content: Text(_action == 'receipt'
                    ? 'Record the time you physically received the item? Inspection can be completed afterward.'
                    : _action == 'release'
                        ? 'Confirm the customer received the prepared equipment? The rental timer starts now.'
                        : _action == 'prepare-delivery'
                            ? 'Mark this exact unit ready for delivery? The rental timer will remain stopped.'
                            : _action == 'payment-review'
                                ? 'Confirm the screenshot shows a successful transfer for the rental fee and refundable deposit, then approve the request?'
                                : _action == 'payment-reject'
                                    ? 'Reject this payment screenshot? The customer can upload a corrected one.'
                                    : _action == 'approve'
                                        ? 'Approve this rental request? It will wait for equipment preparation and handoff.'
                                        : 'Save the reviewed details?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Review')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirm'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final id = Uri.encodeComponent(_text(_row['id']));
      String path = '/rentals/$id/$_action';
      Map<String, dynamic> payload = {'requestKey': _key};
      switch (_action) {
        case 'booking':
          path = '/rental-bookings';
          payload.addAll({
            ..._bookingPayload(),
            'expectedQuote': {
              'rentalFee': _quote!['rental_fee'],
              'depositAmount': _quote!['deposit_amount'],
              'billedMinutes': _quote!['billed_minutes']
            }
          });
          break;
        case 'approve':
          path = '/mobile/rentals/$id/review';
          payload.addAll({
            'action': 'APPROVE',
            'paymentVerified': _paymentVerified,
            'depositReceived': _depositReceived,
            'notes': _notes.text
          });
          break;
        case 'payment-review':
        case 'payment-reject':
          path = '/rentals/$id/payment-review';
          payload.addAll(_action == 'payment-review'
              ? {
                  'action': 'VERIFY',
                  'notes': _notes.text,
                }
              : {
                  'action': 'REJECT',
                  'reason': _reason.text.trim(),
                });
          break;
        case 'prepare-delivery':
          payload.addAll({
            'inventoryCode': _inventory.text.trim(),
            if (_manual) 'manualReason': _reason.text.trim(),
          });
          break;
        case 'reject':
          path = '/mobile/rentals/$id/review';
          payload.addAll({'action': 'REJECT', 'reason': _reason.text});
          break;
        case 'release':
          payload.addAll({
            ..._verification.releaseCodes,
            'customerVerified': _customerVerified,
            'paymentVerified': _paymentVerified,
            'depositReceived': _depositReceived,
            'inspection': _inspectionPayload(),
            if (_manual) 'manualReason': _reason.text.trim()
          });
          break;
        case 'receipt':
          payload.addAll({
            'inventoryCode': _inventory.text.trim(),
            'physicalReceiptConfirmed': _receipt,
            if (_manual) 'manualReason': _reason.text.trim()
          });
          break;
        case 'complete-return':
          payload.addAll({
            'penaltyAmount': double.parse(_penalty.text),
            'penaltyReason': _reason.text,
            'inspection': _inspectionPayload()
          });
          break;
        case 'assignment':
          payload.addAll({
            'inventoryCode': _inventory.text.trim(),
            'reason': _reason.text
          });
          break;
        case 'settlement':
          payload.addAll({
            'paymentAmount': double.parse(_payment.text),
            'depositAppliedAmount': double.parse(_applied.text),
            'depositRefundAmount': double.parse(_refund.text),
            'rentalRefundAmount': double.parse(_rentalRefund.text),
            'notes': _notes.text
          });
          break;
      }
      final response =
          await _api.adminRequest(path, method: 'POST', body: payload);
      if (!mounted) return;
      _changed = true;
      if (_action == 'receipt') {
        setState(() {
          _row = {..._row, ..._map(response['rental'])};
          _action = 'complete-return';
          _key = MobileApiService.operationKey();
          _busy = false;
          _reason.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Physical receipt recorded. The timer has stopped.')));
      } else {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _busy = false;
        });
    }
  }

  String get _title => switch (_action) {
        'booking' => 'Create counter rental',
        'approve' => 'Approve rental request',
        'payment-review' => 'Verify QR payment',
        'payment-reject' => 'Reject QR payment proof',
        'prepare-delivery' => 'Prepare for delivery',
        'reject' => 'Reject / cancel rental request',
        'release' => 'Confirm resort handoff',
        'receipt' => 'Record physical receipt',
        'complete-return' => 'Confirm Return',
        'assignment' => 'Change assigned unit',
        'settlement' => 'Payment / refund',
        _ => 'Rental desk'
      };
  @override
  Widget build(BuildContext context) {
    final items = _rows(widget.workspace['items'])
            .where((item) =>
                item['is_active'] != false &&
                item['status'] == 'AVAILABLE' &&
                item['reserved_rental_id'] == null)
            .toList(),
        customers = _rows(widget.workspace['customers'])
            .where((row) => row['is_active'] != false)
            .toList();
    return PopScope<bool>(
        canPop: !_busy && !_verification.busy && !_previewing,
        child: Scaffold(
            appBar: AppBar(
                title: Text(_title),
                leading: IconButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.arrow_back))),
            bottomNavigationBar: RentalActionBar(
              label: _action == 'release' && _verification.step < 2
                  ? 'Verify customer rental'
                  : _action == 'booking' && _quote == null
                      ? 'Preview price'
                      : _title,
              busy: _busy || _verification.busy || _previewing,
              onPressed: _action == 'release' && _verification.step < 2
                  ? () {
                      if (_form.currentState!.validate())
                        _verification.verify();
                    }
                  : _action == 'booking' && _quote == null
                      ? _preview
                      : _submit,
              summaryLabel: _action == 'booking' && _quote != null
                  ? 'Due at handoff'
                  : null,
              summaryValue: _quote == null
                  ? null
                  : _money(_number(_quote!['rental_fee']) +
                      _number(_quote!['deposit_amount'])),
              secondary: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_error.isNotEmpty || _verification.error.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          _verification.error.isNotEmpty
                              ? _verification.error
                              : _error,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12),
                          textAlign: TextAlign.center)),
                if (_action == 'release' && _verification.step > 0)
                  TextButton.icon(
                      onPressed: _busy || _verification.busy
                          ? null
                          : _verification.back,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back a step')),
              ]),
            ),
            body: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                child: Form(
                    key: _form,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_row.isNotEmpty) ...[
                            Text(
                                '${_row['item_name']} · ${_row['customer_name']}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(_text(_row['rental_code'])),
                            const SizedBox(height: 12)
                          ],
                          if (_action == 'booking') ...[
                            DropdownButtonFormField<String>(
                                initialValue: _itemId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Available equipment'),
                                items: [
                                  for (final row in items)
                                    DropdownMenuItem(
                                        value: _text(row['id']),
                                        child: Text(
                                            '${row['name']} · ${row['item_code']}'))
                                ],
                                validator: (value) =>
                                    value == null ? 'Select equipment' : null,
                                onChanged: _busy || _previewing
                                    ? null
                                    : (value) => setState(() {
                                          _itemId = value;
                                          _quote = null;
                                          _quoteVersion++;
                                        })),
                            DropdownButtonFormField<String>(
                                initialValue: _customerId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Customer'),
                                items: [
                                  for (final row in customers)
                                    DropdownMenuItem(
                                        value: _text(row['id']),
                                        child: Text(_text(row['full_name'])))
                                ],
                                validator: (value) =>
                                    value == null ? 'Select customer' : null,
                                onChanged: _busy || _previewing
                                    ? null
                                    : (value) =>
                                        setState(() => _customerId = value)),
                            _field(_minutes, 'Duration in minutes',
                                numeric: true),
                            _field(_location, 'Delivery location'),
                            DropdownButtonFormField<String>(
                                initialValue: _method,
                                decoration: const InputDecoration(
                                    labelText: 'Payment method'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'CASH', child: Text('Cash')),
                                  DropdownMenuItem(
                                      value: 'QR', child: Text('InstaPay QR'))
                                ],
                                onChanged: _busy || _previewing
                                    ? null
                                    : (value) =>
                                        setState(() => _method = value!)),
                            if (_quote != null)
                              RentalSection(
                                  title: 'Price summary',
                                  child: Column(children: [
                                    RentalValueRow('Rental fee',
                                        _money(_quote!['rental_fee'])),
                                    RentalValueRow('Refundable deposit',
                                        _money(_quote!['deposit_amount'])),
                                    RentalValueRow('Package duration',
                                        '${_quote!['billed_minutes']} minutes'),
                                  ])),
                            const RentalNotice(
                                message:
                                    'Choosing a payment method does not confirm payment. Record only money actually received.'),
                          ],
                          if (_action == 'payment-review') ...[
                            RentalSection(
                                title: 'Customer InstaPay screenshot',
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text('Expected total: ${_money(_number(_row['rental_fee']) + _number(_row['deposit_amount']))}'),
                                      if (_paymentProofLoading)
                                        const Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Center(
                                                child:
                                                    CircularProgressIndicator())),
                                      if (!_paymentProofLoading &&
                                          _paymentProof == null)
                                        Text(_error.isEmpty
                                            ? 'No payment proof found.'
                                            : _error),
                                      if ((_paymentProof?['reference'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Text('Transfer reference: ${_paymentProof!['reference']}'),
                                      if ((_paymentProof?['image_data_url'] ?? '')
                                          .toString()
                                          .startsWith('data:image/'))
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            child: Image.memory(
                                                base64Decode(_text(
                                                        _paymentProof![
                                                            'image_data_url'])
                                                    .split(',')
                                                    .last),
                                                fit: BoxFit.contain,
                                                height: 300)),
                                      _check(
                                          'Screenshot shows a successful transfer for the exact rental total',
                                          _paymentVerified,
                                          (value) => _paymentVerified = value),
                                      _field(_notes, 'Review note',
                                          required: false),
                                    ])),
                          ],
                          if (_action == 'payment-reject')
                            _field(_reason, 'Why this proof is invalid'),
                          if (_action == 'prepare-delivery') ...[
                            RentalNotice(
                                title: 'Shop preparation',
                                icon: Icons.inventory_2_outlined,
                                message:
                                    'Scan the QR sticker on the exact assigned unit before loading it for ${_text(_row['delivery_location']).isEmpty ? 'delivery' : _text(_row['delivery_location'])}. This does not start the rental timer.'),
                            _qr(_inventory, 'Assigned equipment QR at the shop'),
                            _manualControl(),
                          ],
                          if (_action == 'approve') ...[
                            const Text(
                                'Approval holds the assigned unit. Any cash payment and deposit are collected at handoff.'),
                            RentalValueRow(
                                'Rental fee', _money(_row['rental_fee'])),
                            RentalValueRow('Refundable deposit',
                                _money(_row['deposit_amount'])),
                            _check(
                                'Rental payment already received and verified',
                                _paymentVerified,
                                (value) => _paymentVerified = value),
                            _check(
                                'Refundable deposit already received',
                                _depositReceived,
                                (value) => _depositReceived = value),
                            _field(_notes, 'Review notes', required: false)
                          ],
                          if (_action == 'reject')
                            _field(_reason, 'Reason (optional)',
                                required: false),
                          if (_action == 'release') ..._releaseFields(),
                          if (_action == 'receipt') ...[
                            _qr(_inventory, 'Returned inventory QR'),
                            _manualControl(),
                            _check('I physically received this equipment.',
                                _receipt, (value) => _receipt = value)
                          ],
                          if (_action == 'complete-return') ...[
                            RentalNotice(
                                title: 'Rental clock stopped',
                                icon: Icons.task_alt,
                                message:
                                    'Received ${_date(_row['received_at'])}. Overtime ends at this time.'),
                            const SizedBox(height: 16),
                            _inspection(false),
                            _field(_penalty,
                                'Damage / missing-part penalty (0 if none)',
                                numeric: true),
                            _field(_reason, 'Penalty reason',
                                required: _number(_penalty.text) > 0)
                          ],
                          if (_action == 'assignment') ...[
                            _qr(_inventory, 'Replacement inventory QR or code'),
                            _field(_reason, 'Unit change reason')
                          ],
                          if (_action == 'settlement') ...[
                            Text(
                                'Balance ${_money(_row['balance_due'])} · Refund due ${_money(_row['refund_due'])}'),
                            _field(_payment, 'Additional payment received',
                                numeric: true),
                            _field(_applied, 'Deposit applied to charges',
                                numeric: true),
                            _field(_refund, 'Deposit refund paid',
                                numeric: true),
                            if (_row['status'] != 'COMPLETED')
                              _field(_rentalRefund, 'Rental payment refunded',
                                  numeric: true),
                            _field(_notes, 'Receipt / settlement notes')
                          ],
                          const SizedBox(height: 16),
                        ])))));
  }
}
