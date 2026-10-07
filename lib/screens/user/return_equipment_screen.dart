import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';

class ReturnEquipmentScreen extends StatefulWidget {
  const ReturnEquipmentScreen({super.key, required this.rental, this.api});
  final RentalModel rental;
  final MobileApiService? api;
  @override
  State<ReturnEquipmentScreen> createState() => _ReturnEquipmentScreenState();
}

class _ReturnEquipmentScreenState extends State<ReturnEquipmentScreen> {
  String _selectedCondition = 'GOOD';
  final _notes = TextEditingController();
  bool _busy = false;
  String _error = '';
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await (widget.api ?? MobileApiService.instance).requestReturn(
          rentalId: widget.rental.rentalId,
          condition: _selectedCondition,
          notes: _notes.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Return request sent. Bring the equipment to the admin.')));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Request return')),
          bottomNavigationBar: RentalActionBar(
              label: 'Send return request', onPressed: _submit, busy: _busy),
          body: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RentalSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(widget.rental.itemName,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(widget.rental.rentalCode.isEmpty
                        ? widget.rental.rentalId
                        : widget.rental.rentalCode),
                    const Divider(height: 24),
                    RentalValueRow(
                        'Return by',
                        widget.rental.dueDate.millisecondsSinceEpoch > 0
                            ? DateFormat('MMM d · h:mm a')
                                .format(widget.rental.dueDate.toLocal())
                            : 'Not recorded'),
                  ])),
              const RentalNotice(
                  title: 'The clock stops at physical receipt',
                  icon: Icons.assignment_return_outlined,
                  message:
                      'Send this request, then hand the equipment to the admin. They will scan it, record receipt and inspect it.'),
              const SizedBox(height: 16),
              RentalSection(
                title: 'How is the equipment?',
                subtitle: 'This helps the admin prepare the return inspection.',
                icon: Icons.fact_check_outlined,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final option in {
                          'GOOD': 'Good',
                          'NEEDS_INSPECTION': 'Needs checking',
                          'DAMAGED': 'Damaged'
                        }.entries)
                          ChoiceChip(
                              label: Text(option.value),
                              selected: _selectedCondition == option.key,
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(
                                      () => _selectedCondition = option.key)),
                      ]),
                      const SizedBox(height: 18),
                      TextField(
                          controller: _notes,
                          enabled: !_busy,
                          maxLines: 3,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                              labelText: 'Condition notes (optional)',
                              hintText:
                                  'Tell us about scratches, damage or missing parts.')),
                    ]),
              ),
              const RentalNotice(
                  title: 'Final charges and deposit',
                  message:
                      'The admin will confirm any late or damage charges after inspection and record the deposit refund.'),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                RentalNotice(
                    isError: true,
                    title: 'Could not send return request',
                    message: _error),
              ],
              const SizedBox(height: 16),
            ]),
          ),
        ),
      );
}
