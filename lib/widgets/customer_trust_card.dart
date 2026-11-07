import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mobile_api_service.dart';
import 'rental_ui.dart';

class CustomerTrustCard extends StatefulWidget {
  const CustomerTrustCard(
      {super.key, required this.customerId, required this.api});
  final String customerId;
  final MobileApiService api;
  @override
  State<CustomerTrustCard> createState() => _CustomerTrustCardState();
}

class _CustomerTrustCardState extends State<CustomerTrustCard> {
  Map<String, dynamic>? _trust;
  String _error = '';
  int _version = 0;
  StreamSubscription<Map<String, dynamic>>? _events;
  @override
  void initState() {
    super.initState();
    _load();
    _events = widget.api.watchRentalEvents().listen((event) {
      if (['rental.changed', 'customer.changed', 'ready']
          .contains(event['event'])) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(CustomerTrustCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customerId != widget.customerId) {
      _trust = null;
      _load();
    }
  }

  Future<void> _load() async {
    final version = ++_version;
    try {
      final result = await widget.api.adminRequest(
          '/customers/${Uri.encodeComponent(widget.customerId)}/trust');
      if (mounted && version == _version) {
        setState(() {
          _trust = Map<String, dynamic>.from(result['trust'] as Map);
          _error = '';
        });
      }
    } catch (_) {
      if (mounted && version == _version) {
        setState(() => _error = 'Customer history could not be refreshed.');
      }
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: RentalSection(
        title: 'Customer trust',
        icon: Icons.verified_user_outlined,
        child: _trust == null
            ? Text(_error.isEmpty ? 'Loading customer history…' : _error)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Completed rentals: ${_trust!['completed_rentals']}'),
                Text('Active overdue warnings: ${_trust!['active_overdue']}',
                    style: TextStyle(
                        color: (_trust!['active_overdue'] as num? ?? 0) > 0
                            ? Theme.of(context).colorScheme.error
                            : null)),
                Text(_trust!['physical_id_verified'] == true
                    ? 'Physical ID verified by staff'
                    : 'Physical ID has not been verified by staff'),
                if (_error.isNotEmpty) Text(_error),
              ]),
      ));
}
