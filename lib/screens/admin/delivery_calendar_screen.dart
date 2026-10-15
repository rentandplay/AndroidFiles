import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/mobile_api_service.dart';

class DeliveryCalendarScreen extends StatefulWidget {
  const DeliveryCalendarScreen({super.key, required this.api});
  final MobileApiService api;
  @override
  State<DeliveryCalendarScreen> createState() => _DeliveryCalendarScreenState();
}

class _DeliveryCalendarScreenState extends State<DeliveryCalendarScreen> {
  String _day = DateFormat('yyyy-MM-dd')
      .format(DateTime.now().toUtc().add(const Duration(hours: 8)));
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  String _error = '';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api
          .adminRequest('/records/rentals?${Uri(queryParameters: {
            'status': 'OPEN',
            'scheduledDay': _day,
            'limit': '5',
            if (more && _cursor != null) 'cursor': _cursor!
          }).query}');
      if (!mounted) return;
      setState(() {
        final rows = (result['records'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _rows = more ? [..._rows, ...rows] : rows;
        _cursor = result['nextCursor'];
        _error = '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _progress(Map<String, dynamic> row) =>
      switch (row['delivery_status']) {
        'OUT_FOR_DELIVERY' => 'On the way',
        'DELIVERY_FAILED' => 'Unsuccessful · receive at shop',
        'PREPARED' => 'Prepared',
        _ => row['status'] == 'ACTIVE'
            ? 'Delivered · rental active'
            : row['status'] == 'APPROVED'
                ? 'Confirmed schedule'
                : 'Waiting for review',
      };
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Local delivery plan')),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'Within Lakewood Subdivision, Los Baños, Laguna. Prepare within 10 minutes of the scheduled time. The rental timer starts at physical handoff.'),
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_day),
                trailing: const Icon(Icons.event),
                onTap: _busy
                    ? null
                    : () async {
                        final day = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(_day),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now()
                                .toUtc()
                                .add(const Duration(hours: 8, days: 180)));
                        if (day != null && mounted) {
                          setState(() {
                            _day = DateFormat('yyyy-MM-dd').format(day);
                            _rows = [];
                            _cursor = null;
                          });
                          _load();
                        }
                      }),
            if (_busy) const LinearProgressIndicator(),
            if (_error.isNotEmpty) ...[
              Text(_error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              TextButton(
                  onPressed: _busy ? null : _load, child: const Text('Retry'))
            ],
            for (final row in _rows)
              Card(
                  child: ListTile(
                      onTap: _busy ? null : () => Navigator.pop(context, row),
                      title:
                          Text('${row['rental_code']} · ${row['item_name']}'),
                      subtitle: Text(
                          '${DateFormat('h:mm a').format(DateTime.parse(row['scheduled_start_at']).toUtc().add(const Duration(hours: 8)))} · ${row['customer_name']}\n${row['delivery_location']}\n${_progress(row)}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right))),
            if (_rows.isEmpty && !_busy && _error.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No scheduled handoffs for this day.')),
            if (_cursor != null)
              OutlinedButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: const Text('Load more schedules')),
          ])));
}
