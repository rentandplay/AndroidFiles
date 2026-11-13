import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/mobile_api_service.dart';
import '../../utils/error_sanitizer.dart';

String _formatExtensionDuration(int minutes) {
  if (minutes < 60) return '$minutes minutes';
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hour' : '$hours hours';
  }
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  return '${hours}h ${mins}m';
}

Future<bool> showRentalExtensionDialog(
    BuildContext context, MobileApiService api, String rentalId,
    {bool staff = false}) async {
  int minutes = 60;
  bool customerAgreed = false;
  final prefix = staff ? '/rentals' : '/mobile/rentals';
  bool busy = false;
  String error = '';
  Map<String, dynamic>? quote;
  String requestKey = MobileApiService.operationKey();
  return await showDialog<bool>(
          context: context,
          builder: (dialog) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                    title: const Text('Request more rental time'),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text(
                              'Request before your due time. The operator checks the next reservation before approval.'),
                          DropdownButtonFormField<int>(
                              initialValue: minutes,
                              items: [15, 30, 60, 120, 180, 360, 720, 1440]
                                  .map((value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(
                                          _formatExtensionDuration(value))))
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (value) => setState(() {
                                        minutes = value!;
                                        quote = null;
                                        error = '';
                                        customerAgreed = false;
                                        requestKey =
                                            MobileApiService.operationKey();
                                      })),
                          if (quote != null) ...[
                            const SizedBox(height: 12),
                            Text(
                                'Additional charge: ₱${(quote!['additional_fee'] as num).toStringAsFixed(2)}'),
                            Text(
                                'Added time: ${_formatExtensionDuration((quote!['billed_minutes'] as num).round())} (${quote!['billed_minutes']} minutes)'),
                            Text(
                                'New due time: ${DateFormat('MMM d · h:mm a').format(DateTime.parse(quote!['due_at']).toUtc().add(const Duration(hours: 8)))}'),
                            const SizedBox(height: 4),
                            const Text(
                                'The added balance is collected in person or verified through QR. The current due time applies until approval.')
                          ],
                          if (staff)
                            CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: customerAgreed,
                                onChanged: busy
                                    ? null
                                    : (value) =>
                                        setState(() => customerAgreed = value!),
                                title: const Text(
                                    'The customer requested this extension and agreed to the additional charge')),
                          if (error.isNotEmpty)
                            Text(error,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ])),
                    actions: [
                      TextButton(
                          onPressed:
                              busy ? null : () => Navigator.pop(dialog, false),
                          child: const Text('Back')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() {
                                    busy = true;
                                    error = '';
                                  });
                                  try {
                                    if (quote == null) {
                                      final result = await api.adminRequest(
                                          '$prefix/${Uri.encodeComponent(rentalId)}/extension-quote',
                                          method: 'POST',
                                          body: {
                                            'requestKey': requestKey,
                                            'additionalMinutes': minutes
                                          });
                                      if (!context.mounted) return;
                                      setState(() => quote =
                                          Map<String, dynamic>.from(
                                              result['quote'] as Map));
                                    } else {
                                      if (staff && !customerAgreed) {
                                        throw Exception(
                                            'Confirm the customer agreed to this extension.');
                                      }
                                      await api.adminRequest(
                                          '$prefix/${Uri.encodeComponent(rentalId)}/extension',
                                          method: 'POST',
                                          body: {
                                            'requestKey': requestKey,
                                            'additionalMinutes': minutes,
                                            'expectedAdditionalFee':
                                                quote!['additional_fee'],
                                            if (staff)
                                              'customerRequestedExtension':
                                                  customerAgreed
                                          });
                                      if (dialog.mounted) {
                                        Navigator.pop(dialog, true);
                                      }
                                    }
                                  } catch (problem) {
                                    if (context.mounted) {
                                      setState(() => error =
                                          ErrorSanitizer.format(problem));
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setState(() => busy = false);
                                    }
                                  }
                                },
                          child: Text(busy
                              ? (quote == null
                                  ? 'Checking…'
                                  : 'Sending request…')
                              : quote == null
                                  ? 'Review price'
                                  : 'Agree & request extension'))
                    ],
                  ))) ??
      false;
}
