import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_api_service.dart';
import 'money_entry_dialog.dart';
import 'historical_receipt_dialog.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.api});
  final AdminFirestoreService api;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  bool _busy = false, _ledger = false;
  String _error = '';
  late DateTimeRange _range;
  final _day = DateFormat('yyyy-MM-dd');
  String _money(dynamic value) => value == null
      ? 'Not recorded'
      : '₱${NumberFormat('#,##0.00').format(value)}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final end = DateTime(now.year, now.month, now.day);
    _range =
        DateTimeRange(start: end.subtract(const Duration(days: 29)), end: end);
    _load();
  }

  Future<void> _load({bool more = false, bool force = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    final query = Uri(queryParameters: {
      'from': _day.format(_range.start),
      'to': _day.format(_range.end),
      'limit': '5',
      if (more && _cursor != null) 'cursor': _cursor!,
    }).query;
    try {
      final result = await Future.wait([
        if (!more)
          widget.api.getMap('/finance/summary?$query', forceRefresh: force),
        widget.api.getMap('/finance/${_ledger ? 'ledger' : 'rentals'}?$query',
            forceRefresh: force),
      ]);
      if (!mounted) return;
      final page = result.last;
      final rows = (page[_ledger ? 'entries' : 'records'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      setState(() {
        if (!more) _summary = result.first;
        _rows = more ? [..._rows, ...rows] : rows;
        _cursor = page['nextCursor'];
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _entry({bool receipt = false, String code = ''}) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MoneyEntryDialog(
            api: widget.api, receipt: receipt, initialRentalCode: code));
    if (saved == true && mounted) await _load(force: true);
  }

  Future<void> _history(Map<String, dynamic> rental) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            HistoricalReceiptDialog(api: widget.api, rental: rental));
    if (saved == true && mounted) await _load(force: true);
  }

  Future<void> _chooseRange() async {
    final picked = await showDateRangePicker(
        context: context,
        initialDateRange: _range,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        helpText: 'Payment period');
    if (picked == null || !mounted) return;
    if (picked.duration.inDays > 366) {
      setState(() => _error = 'Choose up to one year.');
      return;
    }
    setState(() {
      _range = picked;
      _summary = null;
      _rows = [];
      _cursor = null;
    });
    await _load();
  }

  Widget _metric(String title, dynamic amount, {bool accent = false}) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 10),
            Text(_money(amount),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        accent ? Theme.of(context).colorScheme.primary : null)),
          ])));

  Widget _rentalCard(Map<String, dynamic> row) {
    final f = row['finance'] as Map;
    final unposted = (f['unposted_paid'] as num?) ?? 0,
        balance = (f['balance_due'] as num?) ?? 0;
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(
                        '${row['rental_code'] ?? 'Rental'} · ${row['item_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                if (unposted > 0) const Icon(Icons.history_outlined, size: 20)
              ]),
              const SizedBox(height: 5),
              Text('${row['customer_name']} · ${row['status']}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Divider(height: 24),
              Wrap(spacing: 22, runSpacing: 12, children: [
                for (final item in {
                  'Charges': f['charges'],
                  'Saved paid': f['saved_paid'],
                  'Balance': f['balance_due']
                }.entries)
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.key,
                            style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(_money(item.value),
                            style: const TextStyle(fontWeight: FontWeight.w600))
                      ]),
              ]),
              if ((f['refund_due'] as num? ?? 0) > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child:
                        Text('Refund to return: ${_money(f['refund_due'])}')),
              if (unposted > 0) ...[
                const SizedBox(height: 14),
                Text(
                    '${_money(unposted)} is already saved as paid. Its original receipt date is missing.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _busy ? null : () => _history(row),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: const Text('Add original receipt date'))
              ],
              if (f['saved_paid'] == null)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                        'Payment amount not recorded. Review the original rental.')),
              if (balance > 0)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => _entry(
                            receipt: true, code: row['rental_code'] ?? ''),
                    child: const Text('Collect outstanding balance')),
            ])));
  }

  Widget _ledgerCard(Map<String, dynamic> row) {
    final occurred = DateTime.tryParse(row['occurred_at'] ?? '');
    final date = occurred == null
        ? 'Date not recorded'
        : DateFormat('MMM d, yyyy · h:mm a')
            .format(occurred.toUtc().add(const Duration(hours: 8)));
    return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text('${row['ledger_code']} · ${_money(row['amount'])}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${row['type']} · ${row['payment_method']}\n${row['rental_code'] ?? row['category'] ?? 'Expense'} · $date\n${row['reference'] ?? row['notes'] ?? ''}'),
            isThreeLine: true));
  }

  @override
  Widget build(BuildContext context) {
    final totals = _summary?['totals'] as Map? ?? {},
        rental = _summary?['rental_totals'] as Map? ?? {};
    return Scaffold(
        appBar: AppBar(title: const Text('Payments & expenses'), actions: [
          IconButton(
              onPressed: _busy ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh payments')
        ]),
        body: RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Payment overview',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            const Text(
                                'Saved rental payments, actual receipts, and expenses.'),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                                onPressed: _busy ? null : _chooseRange,
                                icon: const Icon(Icons.date_range),
                                label: Text(
                                    '${DateFormat('MMM d').format(_range.start)} – ${DateFormat('MMM d, yyyy').format(_range.end)}')),
                            const SizedBox(height: 10),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _entry(receipt: true),
                                  child: const Text('Record receipt')),
                              FilledButton(
                                  onPressed: _busy ? null : () => _entry(),
                                  child: const Text('Record expense')),
                            ]),
                          ]))),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              if (_error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (_summary != null) ...[
                LayoutBuilder(
                    builder: (context, constraints) =>
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          for (final item in {
                            'Rental charges': rental['charges'],
                            'Saved rental payments': rental['saved_paid'],
                            'Balance to collect': rental['balance_due'],
                            'Refunds to return': rental['refund_due']
                          }.entries)
                            SizedBox(
                                width: (constraints.maxWidth - 12) / 2,
                                child: _metric(item.key, item.value,
                                    accent:
                                        item.key == 'Saved rental payments')),
                        ])),
                if ((rental['unposted_count'] as num? ?? 0) > 0)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                  '${rental['unposted_count']} rentals have ${_money(rental['unposted_paid'])} in saved payments without a receipt date. Review them below; adding the date will not collect money again.')))),
                const SizedBox(height: 12),
                Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Dated money activity',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final item in {
                                'Money collected': totals['collections'],
                                'Money refunded': totals['refunds'],
                                'Expenses paid': totals['expenses'],
                                'After refunds & expenses':
                                    totals['net_after_expenses']
                              }.entries)
                                Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(children: [
                                      Expanded(child: Text(item.key)),
                                      Text(_money(item.value),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600))
                                    ])),
                              const SizedBox(height: 8),
                              Text(
                                  'Receipts use the date money was received. Rental totals use rentals created in this period.',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ]))),
              ],
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Rental payments')),
                    ButtonSegment(value: true, label: Text('Receipt ledger'))
                  ],
                  selected: {
                    _ledger
                  },
                  onSelectionChanged: _busy
                      ? null
                      : (values) {
                          setState(() {
                            _ledger = values.first;
                            _rows = [];
                            _cursor = null;
                          });
                          _load();
                        }),
              const SizedBox(height: 14),
              for (final row in _rows)
                _ledger ? _ledgerCard(row) : _rentalCard(row),
              if (_rows.isEmpty && !_busy && _error.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        _ledger
                            ? 'No dated receipts or expenses in this period. Historical payments remain visible under Rental payments.'
                            : 'No rentals created in this period. Choose a wider date range.',
                        textAlign: TextAlign.center)),
              if (_cursor != null)
                OutlinedButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('Load more')),
            ])));
  }
}
