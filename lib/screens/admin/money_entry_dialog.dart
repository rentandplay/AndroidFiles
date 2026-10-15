import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../services/mobile_api_service.dart';

class MoneyEntryDialog extends StatefulWidget {
  const MoneyEntryDialog(
      {super.key,
      required this.api,
      this.receipt = false,
      this.initialRentalCode = ''});
  final AdminFirestoreService api;
  final bool receipt;
  final String initialRentalCode;
  @override
  State<MoneyEntryDialog> createState() => _MoneyEntryDialogState();
}

class _MoneyEntryDialogState extends State<MoneyEntryDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(),
      _notes = TextEditingController(),
      _reference = TextEditingController(),
      _code = TextEditingController();
  final _key = MobileApiService.operationKey();
  String _method = 'CASH', _category = 'OTHER', _error = '', _foundCode = '';
  Map<String, dynamic>? _rental;
  bool _busy = false, _confirmed = false;
  @override
  void initState() {
    super.initState();
    if (widget.receipt && widget.initialRentalCode.isNotEmpty) {
      _code.text = widget.initialRentalCode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _find();
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _reference.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final code = _code.text.trim().toUpperCase();
      final result = await widget.api
          .post('/rentals/lookup', body: {'kind': 'RENTAL', 'code': code});
      if (mounted) {
        setState(() {
          _rental = Map<String, dynamic>.from(result['rental']);
          _foundCode = code;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (!_confirmed) {
      setState(() => _error = 'Confirm that the money was received or paid.');
      return;
    }
    if (widget.receipt &&
        (_rental == null || _foundCode != _code.text.trim().toUpperCase())) {
      setState(() => _error = 'Find the rental before saving.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.api.post(
          widget.receipt
              ? '/rentals/${Uri.encodeComponent(_rental!['id'])}/settlement'
              : '/finance/expenses',
          body: {
            'requestKey': _key,
            widget.receipt ? 'paymentAmount' : 'amount':
                double.parse(_amount.text.trim()),
            'paymentMethod': _method,
            'reference': _reference.text.trim(),
            'notes': _notes.text.trim(),
            if (!widget.receipt) 'category': _category,
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
          title: Text(widget.receipt
              ? 'Record rental receipt'
              : 'Record an expense paid'),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.receipt
                            ? 'Record cash received in person or a confirmed QR transfer. Approval and delivery are handled separately.'
                            : 'Record an expense that has actually been paid.'),
                        if (widget.receipt) ...[
                          TextFormField(
                              controller: _code,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                  labelText: 'Rental reference',
                                  hintText: 'R-0001'),
                              maxLength: 128,
                              onChanged: (_) => setState(() {
                                    _rental = null;
                                    _foundCode = '';
                                  })),
                          OutlinedButton(
                              onPressed: _busy ? null : _find,
                              child: const Text('Find rental')),
                          if (_rental != null)
                            Text(
                                '${_rental!['rental_code']} · ${_rental!['customer_name']}\n${_rental!['item_name']} · ${_rental!['status']}\nOutstanding: ₱${_rental!['balance_due'] ?? 'Needs review'}'),
                        ],
                        TextFormField(
                            controller: _amount,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: widget.receipt
                                    ? 'Amount received (PHP)'
                                    : 'Amount paid (PHP)'),
                            validator: (value) {
                              final n = double.tryParse(value ?? '');
                              return n == null ||
                                      !n.isFinite ||
                                      n <= 0 ||
                                      n > 9999999999.99 ||
                                      (n * 100 - (n * 100).round()).abs() >
                                          .0001
                                  ? 'Enter a positive amount with up to 2 decimals.'
                                  : null;
                            }),
                        if (!widget.receipt)
                          DropdownButtonFormField<String>(
                              initialValue: _category,
                              decoration:
                                  const InputDecoration(labelText: 'Category'),
                              items: [
                                'DELIVERY',
                                'MAINTENANCE',
                                'SUPPLIES',
                                'UTILITIES',
                                'OTHER'
                              ]
                                  .map((value) => DropdownMenuItem(
                                      value: value, child: Text(value)))
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _category = value!)),
                        DropdownButtonFormField<String>(
                            initialValue: _method,
                            decoration:
                                const InputDecoration(labelText: 'Method'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'CASH',
                                  child: Text('Cash · in person')),
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
                            decoration: const InputDecoration(
                                labelText: 'Description / notes'),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Describe this payment.'
                                : null),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: _busy
                                ? null
                                : (value) =>
                                    setState(() => _confirmed = value!),
                            title: Text(widget.receipt
                                ? 'I confirmed the money was received'
                                : 'This expense has been paid')),
                        if (_error.isNotEmpty)
                          Text(_error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                      ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Back')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy
                    ? 'Saving…'
                    : widget.receipt
                        ? 'Record receipt'
                        : 'Save expense'))
          ],
        ),
      );
}
