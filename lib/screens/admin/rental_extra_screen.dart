import 'package:flutter/material.dart';
import '../../services/mobile_api_service.dart';
import '../shared/qr_capture_screen.dart';

class RentalExtraScreen extends StatefulWidget {
  const RentalExtraScreen(
      {super.key,
      required this.row,
      required this.kind,
      required this.api,
      this.scannedCode});
  final Map<String, dynamic> row;
  final String kind;
  final MobileApiService api;
  final String? scannedCode;
  @override
  State<RentalExtraScreen> createState() => _RentalExtraScreenState();
}

class _RentalExtraScreenState extends State<RentalExtraScreen> {
  final _reason = TextEditingController(),
      _code = TextEditingController(),
      _manual = TextEditingController(),
      _notes = TextEditingController();
  final _key = MobileApiService.operationKey();
  bool _busy = false, _received = false;
  String _error = '', _condition = 'GOOD', _action = '';
  @override
  void initState() {
    super.initState();
    _code.text = widget.scannedCode ?? '';
    _action = widget.kind == 'extension-review'
        ? 'APPROVE'
        : widget.row['delivery_status'] == 'DELIVERY_FAILED'
            ? 'RETURN_TO_SHOP'
            : widget.row['delivery_status'] == 'OUT_FOR_DELIVERY'
                ? 'FAIL'
                : 'DEPART';
  }

  @override
  void dispose() {
    _reason.dispose();
    _code.dispose();
    _manual.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.api.adminRequest(
          '/rentals/${Uri.encodeComponent(widget.row['id'])}/${widget.kind}',
          method: 'POST',
          body: {
            'action': _action,
            'requestKey': widget.kind == 'extension-review'
                ? widget.row['extension_request']['request_key']
                : _key,
            'reason': _reason.text,
            'inventoryCode': _code.text.trim(),
            'manualReason': _manual.text,
            'condition': _condition,
            'notes': _notes.text,
            'physicalReceiptConfirmed': _received
          });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extension = widget.kind == 'extension-review',
        request = widget.row['extension_request'] as Map?;
    return Scaffold(
        appBar: AppBar(
            title: Text(extension ? 'Review extension' : 'Local delivery')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('${widget.row['rental_code']} · ${widget.row['item_name']}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(extension
              ? 'Additional charge: ₱${request?['additional_fee']}\nNew due time: ${request?['requested_due_at']}\nApproval checks the next reservation again. Payment is recorded separately.'
              : 'Within Lakewood Subdivision, Los Baños, Laguna.\n${widget.row['delivery_location']}\nThe rental timer starts at physical customer handoff.'),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
              initialValue: _action,
              decoration: const InputDecoration(labelText: 'Action'),
              items: (extension
                      ? ['APPROVE', 'REJECT']
                      : _action == 'RETURN_TO_SHOP'
                          ? ['RETURN_TO_SHOP']
                          : widget.row['delivery_status'] == 'PREPARED'
                              ? ['DEPART', 'FAIL']
                              : ['FAIL'])
                  .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text({
                        'DEPART': 'Equipment is on the way',
                        'FAIL': 'Delivery unsuccessful',
                        'RETURN_TO_SHOP': 'Equipment received at shop',
                        'APPROVE': 'Approve extension',
                        'REJECT': 'Reject extension'
                      }[value]!)))
                  .toList(),
              onChanged:
                  _busy ? null : (value) => setState(() => _action = value!)),
          if (_action == 'FAIL' || _action == 'REJECT')
            TextField(
                controller: _reason,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Reason')),
          if (_action == 'RETURN_TO_SHOP') ...[
            TextField(
                controller: _code,
                decoration: const InputDecoration(
                    labelText: 'Exact equipment QR or code')),
            OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final code = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const QrCaptureScreen(
                                    title: 'Scan returning equipment')));
                        if (code != null && mounted) {
                          setState(() => _code.text = code);
                        }
                      },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan exact unit')),
            TextField(
                controller: _manual,
                decoration: const InputDecoration(
                    labelText:
                        'Manual lookup reason, if entering a printed code')),
            DropdownButtonFormField<String>(
                initialValue: _condition,
                items: ['GOOD', 'FAIR', 'DAMAGED', 'NEEDS_INSPECTION']
                    .map((value) =>
                        DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _condition = value!)),
            TextField(
                controller: _notes,
                maxLength: 2000,
                decoration: const InputDecoration(
                    labelText: 'Condition notes (required for damage)')),
            CheckboxListTile(
                value: _received,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _received = value!),
                title: const Text('Unit is physically back at the shop')),
          ],
          if (_error.isNotEmpty)
            Text(_error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 20),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Confirm')),
        ]));
  }
}
