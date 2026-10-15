import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_api_service.dart';
import '../../services/mobile_api_service.dart';

class HistoricalReceiptDialog extends StatefulWidget {
  const HistoricalReceiptDialog(
      {super.key, required this.api, required this.rental});
  final AdminFirestoreService api;
  final Map<String, dynamic> rental;
  @override
  State<HistoricalReceiptDialog> createState() =>
      _HistoricalReceiptDialogState();
}

class _HistoricalReceiptDialogState extends State<HistoricalReceiptDialog> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController(), _reference = TextEditingController();
  final _key = MobileApiService.operationKey();
  String _method = 'CASH', _error = '';
  bool _busy = false, _confirmed = false;
  DateTime? _occurred;
  @override
  void initState() {
    super.initState();
    if (widget.rental['payment_method'] == 'QR') _method = 'QR';
  }

  @override
  void dispose() {
    _notes.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final day = await showDatePicker(
        context: context,
        initialDate: _occurred ?? now,
        firstDate: DateTime(2020),
        lastDate: now);
    if (day == null || !mounted) return;
    final time = await showTimePicker(
        context: context,
        initialTime: _occurred == null
            ? const TimeOfDay(hour: 12, minute: 0)
            : TimeOfDay.fromDateTime(_occurred!));
    if (time != null && mounted) {
      setState(() => _occurred =
          DateTime(day.year, day.month, day.day, time.hour, time.minute));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_occurred == null || !_confirmed) {
      setState(() =>
          _error = 'Choose the original receipt time and confirm its details.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final at = _occurred!;
      await widget.api.post(
          '/finance/rentals/${Uri.encodeComponent(widget.rental['id'])}/receipt-history',
          body: {
            'requestKey': _key,
            'amount': (widget.rental['finance'] as Map)['unposted_paid'],
            'paymentMethod': _method,
            'reference': _reference.text.trim(),
            'notes': _notes.text.trim(),
            'confirmed': true,
            'occurredAt':
                DateTime.utc(at.year, at.month, at.day, at.hour, at.minute)
                    .subtract(const Duration(hours: 8))
                    .toIso8601String(),
          });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Confirm original receipt'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${widget.rental['rental_code']} · ${widget.rental['item_name']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(
                          '₱${NumberFormat('#,##0.00').format((widget.rental['finance'] as Map)['unposted_paid'])} is already saved as paid. This adds its original receipt details without increasing the rental payment.'),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          onPressed: _busy ? null : _pickDate,
                          icon: const Icon(Icons.event),
                          label: Text(_occurred == null
                              ? 'Choose original receipt date & time'
                              : DateFormat('MMM d, yyyy · h:mm a')
                                  .format(_occurred!))),
                      const Text('Philippine time',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: _method,
                          decoration:
                              const InputDecoration(labelText: 'Method'),
                          items: const [
                            DropdownMenuItem(
                                value: 'CASH', child: Text('Cash · in person')),
                            DropdownMenuItem(
                                value: 'QR', child: Text('QR transfer'))
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _method = value!)),
                      TextFormField(
                          controller: _reference,
                          enabled: !_busy,
                          maxLength: 150,
                          decoration: const InputDecoration(
                              labelText: 'Transfer reference'),
                          validator: (value) =>
                              _method == 'QR' && (value ?? '').trim().isEmpty
                                  ? 'Enter the confirmed transfer reference.'
                                  : null),
                      TextFormField(
                          controller: _notes,
                          enabled: !_busy,
                          maxLength: 500,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Evidence / notes'),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Describe the original receipt you verified.'
                              : null),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _confirmed,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _confirmed = value!),
                          title: const Text(
                              'I verified the original payment date, amount, and method.')),
                      if (_error.isNotEmpty)
                        Text(_error,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ]))),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Confirm receipt'))
        ],
      ));
}
