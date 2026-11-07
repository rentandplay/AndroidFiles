import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/mobile_api_service.dart';

const String rentalTermsVersion = '2026-10-13-v1';

class TermsDialog extends StatefulWidget {
  const TermsDialog(
      {super.key,
      this.onAccept,
      this.onDecline,
      this.onVersion,
      this.termsText,
      this.readOnly = false,
      this.api});
  final VoidCallback? onAccept, onDecline;
  final ValueChanged<String>? onVersion;
  final String? termsText;
  final bool readOnly;
  final MobileApiService? api;
  static Future<bool?> show(BuildContext context,
          {VoidCallback? onAccept,
          VoidCallback? onDecline,
          ValueChanged<String>? onVersion,
          String? termsText,
          bool readOnly = false,
          MobileApiService? api}) =>
      showDialog<bool>(
          context: context,
          barrierDismissible: readOnly,
          builder: (_) => TermsDialog(
              onAccept: onAccept,
              onDecline: onDecline,
              onVersion: onVersion,
              termsText: termsText,
              readOnly: readOnly,
              api: api));
  @override
  State<TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<TermsDialog> {
  static const sections = {
    'terms_and_conditions': 'Terms & Conditions',
    'rental_terms': 'Rental Agreement',
    'privacy_policy': 'Privacy Policy (DPA 2012)',
    'refund_policy': 'Cancellation & Refund Policy',
  };
  Map<String, dynamic> _terms = {};
  String _section = 'terms_and_conditions', _error = '';
  bool _loading = true;
  int _version = 0;
  StreamSubscription<Map<String, dynamic>>? _events;
  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  @override
  void initState() {
    super.initState();
    _load();
    _events = _api.watchRentalEvents().listen((event) {
      if (event['event'] == 'settings.changed') _load();
    });
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final terms = await _api.terms();
      if (!mounted || version != _version) return;
      setState(() {
        _terms = terms;
        _loading = false;
      });
    } catch (_) {
      if (mounted && version == _version) {
        setState(() {
          _loading = false;
          _error = 'Could not load current store policies. Please retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Store policies'),
        content: SizedBox(
            width: 480,
            height: 400,
            child: Column(children: [
              DropdownButtonFormField<String>(
                  initialValue: _section,
                  isExpanded: true,
                  items: sections.entries
                      .map((section) => DropdownMenuItem(
                          value: section.key, child: Text(section.value)))
                      .toList(),
                  onChanged: (section) {
                    if (section != null) setState(() => _section = section);
                  }),
              const SizedBox(height: 16),
              Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error.isNotEmpty
                          ? Column(children: [
                              Text(_error),
                              TextButton(
                                  onPressed: _load, child: const Text('Retry'))
                            ])
                          : SingleChildScrollView(
                              child: SelectableText(
                                  (_terms[_section] ??
                                          'This policy is not available. Please contact counter staff.')
                                      .toString(),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(height: 1.5)))),
            ])),
        actions: widget.readOnly
            ? [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ]
            : [
                TextButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                      widget.onDecline?.call();
                    },
                    child: const Text('Decline')),
                FilledButton(
                    onPressed: _loading ||
                            _error.isNotEmpty ||
                            (_terms['terms_and_conditions'] ?? '')
                                .toString()
                                .trim()
                                .isEmpty
                        ? null
                        : () {
                            widget.onVersion?.call(
                                (_terms['terms_version'] ?? rentalTermsVersion)
                                    .toString());
                            widget.onAccept?.call();
                            Navigator.pop(context, true);
                          },
                    child: const Text('Accept & Agree')),
              ],
      );
}
