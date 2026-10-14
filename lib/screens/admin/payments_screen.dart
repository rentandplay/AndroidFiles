import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_api_service.dart';
import 'money_entry_dialog.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.api});
  final AdminFirestoreService api;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _entries = [];
  String? _cursor;
  bool _busy = false;
  String _error = '';
  String _day = DateFormat('yyyy-MM-dd')
      .format(DateTime.now().toUtc().add(const Duration(hours: 8)));
  @override
  void initState() {
    super.initState();
    _load();
  }

  String _money(dynamic value) =>
      '₱${((value as num?) ?? 0).toStringAsFixed(2)}';
  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final summary =
          await widget.api.getMap('/finance/summary?from=$_day&to=$_day');
      final page =
          await widget.api.getMap('/finance/ledger?${Uri(queryParameters: {
            'from': _day,
            'to': _day,
            'limit': '25',
            if (more && _cursor != null) 'cursor': _cursor!
          }).query}');
      if (!mounted) return;
      setState(() {
        _summary = summary;
        final rows = (page['entries'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _entries = more ? [..._entries, ...rows] : rows;
        _cursor = page['nextCursor'];
        _error = '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _entry({bool receipt = false}) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MoneyEntryDialog(api: widget.api, receipt: receipt));
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final totals = _summary?['totals'] as Map? ?? {};
    return Scaffold(
        appBar: AppBar(title: const Text('Payments & expenses'), actions: [
          IconButton(
              onPressed: _busy ? null : () => _entry(),
              icon: const Icon(Icons.add),
              tooltip: 'Record expense'),
          IconButton(
              onPressed: _busy ? null : () => _entry(receipt: true),
              icon: const Icon(Icons.payments_outlined),
              tooltip: 'Record rental receipt'),
        ]),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(
                  title: Text('Daily cash summary · $_day'),
                  subtitle: const Text(
                      'Cash accepted in person; QR transfers confirmed by staff.'),
                  trailing: const Icon(Icons.event),
                  onTap: _busy
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                              context: context,
                              initialDate: DateTime.parse(_day),
                              firstDate: DateTime(2020),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 1)));
                          if (selected != null && mounted) {
                            setState(() {
                              _day = DateFormat('yyyy-MM-dd').format(selected);
                              _summary = null;
                              _entries = [];
                              _cursor = null;
                            });
                            _load();
                          }
                        }),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final entry in {
                  'Collected': totals['collections'],
                  'Refunded': totals['refunds'],
                  'Expenses paid': totals['expenses'],
                  'Net collected': totals['net_collected'],
                  'Net cash recorded': totals['cash_net_movement'],
                  'After recorded expenses': totals['net_after_expenses']
                }.entries)
                  SizedBox(
                      width: 155,
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.key),
                                    Text(_money(entry.value),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge)
                                  ]))))
              ]),
              const SizedBox(height: 12),
              const Text(
                  'Only recorded ledger receipts are included. Historical payments without a recorded receipt time are excluded. Rental balances and refunds are handled from each rental.'),
              if (_error.isNotEmpty) ...[
                Text(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(onPressed: () => _load(), child: const Text('Retry'))
              ],
              if (_busy) const LinearProgressIndicator(),
              for (final row in _entries)
                Card(
                    child: ListTile(
                        title: Text(
                            '${row['ledger_code']} · ${_money(row['amount'])}'),
                        subtitle: Text(
                            '${row['type']} · ${row['payment_method']}\n${row['rental_code'] ?? row['category'] ?? 'Expense'} · ${row['reference'] ?? row['notes'] ?? ''}\n${row['recorded_by_name'] ?? 'Staff'}'),
                        isThreeLine: true)),
              if (_entries.isEmpty && !_busy)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No receipts recorded for this day.')),
              if (_cursor != null)
                OutlinedButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('Load more receipts'))
            ])));
  }
}
