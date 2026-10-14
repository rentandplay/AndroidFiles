import 'package:flutter/material.dart';

import '../../services/admin_firestore_service.dart';
import '../../utils/maintenance_state.dart';
import '../../utils/record_codes.dart';
import '../shared/equipment_qr_label_dialog.dart';
import 'maintenance_screen.dart';

class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({
    super.key,
    required this.items,
    required this.onRefresh,
    this.loadItems,
  });

  final List<Map<String, dynamic>> items;
  final Future<void> Function() onRefresh;
  final Future<List<Map<String, dynamic>>> Function()? loadItems;

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  String _search = '';
  String _category = 'All';
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
  }

  @override
  void didUpdateWidget(covariant EquipmentListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _items = widget.items;
  }

  Future<void> _refresh() async {
    try {
      await widget.onRefresh();
      final items = await widget.loadItems?.call();
      if (mounted && items != null) setState(() => _items = items);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not refresh equipment. $error')));
      }
    }
  }

  List<String> get _categories {
    final values = _items
        .map((item) => item['category']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...values];
  }

  List<Map<String, dynamic>> get _visibleItems {
    final query = _search.trim().toLowerCase();
    return _items.where((item) {
      final itemCategory = item['category']?.toString() ?? 'Uncategorized';
      final matchesCategory = _category == 'All' || itemCategory == _category;
      final searchable = [
        item['name'],
        item['item_code'],
        item['qrCode'],
        item['category'],
        item['description'],
      ].whereType<Object>().join(' ').toLowerCase();
      return matchesCategory && (query.isEmpty || searchable.contains(query));
    }).toList();
  }

  Future<void> _showDetails(Map<String, dynamic> item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _EquipmentDetailsSheet(
        item: item,
        api: AdminFirestoreService.instance,
        onMaintenanceChanged: _refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = _categories;
    if (!categories.contains(_category)) _category = 'All';
    final items = _visibleItems;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            'Equipment list',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_items.length} units · View details and print equipment labels',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: 'Search name or equipment code',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final value = categories[index];
                return ChoiceChip(
                  label: Text(value),
                  selected: _category == value,
                  onSelected: (_) => setState(() => _category = value),
                  selectedColor: const Color(0xFFFFE8D7),
                  labelStyle: TextStyle(
                    color: _category == value
                        ? const Color(0xFFC45E1B)
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        _category == value ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: BorderSide.none,
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 56),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 42, color: theme.colorScheme.outline),
                  const SizedBox(height: 10),
                  Text(
                    _items.isEmpty
                        ? 'No equipment found.'
                        : 'No equipment matches this search.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            ...items.map((item) => _EquipmentCard(
                  item: item,
                  onTap: () => _showDetails(item),
                )),
        ],
      ),
    );
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _first(item, ['item_code', 'qrCode', 'qr_code']);
    final category = _first(item, ['category']) ?? 'Uncategorized';
    final status = _first(item, ['effective_status', 'status']) ?? 'UNKNOWN';
    final available = status.toUpperCase() == 'AVAILABLE';

    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF2E7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.sports_basketball_outlined,
              color: Color(0xFFC45E1B)),
        ),
        title: Text(
          _first(item, ['name']) ?? 'Equipment',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([if (code != null) code, category].join(' · ')),
              const SizedBox(height: 5),
              _StatusPill(label: _prettyStatus(status), available: available),
            ],
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

class _EquipmentDetailsSheet extends StatefulWidget {
  const _EquipmentDetailsSheet(
      {required this.item,
      required this.api,
      required this.onMaintenanceChanged});

  final Map<String, dynamic> item;
  final AdminFirestoreService api;
  final Future<void> Function() onMaintenanceChanged;

  @override
  State<_EquipmentDetailsSheet> createState() => _EquipmentDetailsSheetState();
}

class _EquipmentDetailsSheetState extends State<_EquipmentDetailsSheet> {
  late Future<Map<String, dynamic>> _detail;
  bool _loadingQr = false;
  String _qrError = '';

  @override
  void initState() {
    super.initState();
    _detail = _loadDetails();
  }

  Future<Map<String, dynamic>> _loadDetails() {
    final id = widget.item['id']?.toString() ?? '';
    return id.isEmpty
        ? Future.value({'item': widget.item})
        : widget.api.getMap('/inventory/${Uri.encodeComponent(id)}',
            forceRefresh: true);
  }

  Future<void> _maintenance({String? ticketId}) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ticketId == null
                ? MaintenanceEditScreen(
                    api: widget.api, unitId: widget.item['id']?.toString())
                : MaintenanceTicketScreen(id: ticketId, api: widget.api)));
    if (mounted) {
      setState(() {
        _detail = _loadDetails();
      });
      await widget.onMaintenanceChanged();
    }
  }

  Future<void> _printQr(Map<String, dynamic> item) async {
    if (_loadingQr) return;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) {
      setState(() => _qrError =
          'Equipment ID is missing. Refresh the list and try again.');
      return;
    }
    setState(() {
      _loadingQr = true;
      _qrError = '';
    });
    try {
      final result = await widget.api.getMap(
        '/inventory/${Uri.encodeComponent(id)}/qr',
      );
      if (!mounted) return;
      final rawMatrix = result['matrix'];
      final qrCode = result['code']?.toString().trim() ?? '';
      final qrToken = result['token']?.toString().trim() ?? '';
      if (qrCode.isEmpty || qrToken.isEmpty) {
        throw const AdminApiException(
            'The QR label is incomplete. Refresh and try again.');
      }
      final qrMatrix = rawMatrix is Map
          ? rawMatrix.map((key, value) => MapEntry('$key', value))
          : null;
      await EquipmentQrLabelDialog.show(
        context,
        qrCode: qrCode,
        qrData: qrToken,
        qrMatrix: qrMatrix,
        itemName:
            result['name']?.toString() ?? _first(item, ['name']) ?? 'Equipment',
      );
    } on AdminApiException catch (error) {
      if (mounted) setState(() => _qrError = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _qrError = 'Could not prepare the QR label: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingQr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: _detail,
        builder: (context, snapshot) {
          final detail = snapshot.data?['item'];
          final item = detail is Map
              ? detail.map((key, value) => MapEntry('$key', value))
              : widget.item;
          final code = _first(item, ['item_code', 'qrCode', 'qr_code']);
          final status =
              _first(item, ['effective_status', 'status']) ?? 'UNKNOWN';
          final condition = _first(item, ['condition_status', 'condition']);
          final rates = snapshot.data?['rates'];
          final maintenance = snapshot.data?['maintenance'];

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _first(item, ['name']) ?? 'Equipment details',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (code != null)
                        _StatusPill(label: code, available: true),
                      _StatusPill(
                        label: _prettyStatus(status),
                        available: status.toUpperCase() == 'AVAILABLE',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _detail = _loadDetails();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh latest details'),
                    ),
                  ),
                  _DetailRow(
                    label: 'Category',
                    value: _first(item, ['category']) ?? 'Uncategorized',
                  ),
                  if (condition != null)
                    _DetailRow(
                        label: 'Condition', value: _prettyStatus(condition)),
                  _DetailRow(
                    label: 'Rental rate',
                    value: _money(item['rental_rate']) +
                        (_first(item, ['rate_type']) == null
                            ? ''
                            : ' / ${_first(item, [
                                    'rate_type'
                                  ])!.toLowerCase()}'),
                  ),
                  if (item['open_rentals'] != null)
                    _DetailRow(
                      label: 'Open rentals',
                      value: item['open_rentals'].toString(),
                    ),
                  if (item['open_maintenance'] != null)
                    _DetailRow(
                      label: 'Open maintenance',
                      value: item['open_maintenance'].toString(),
                    ),
                  if (item['total_quantity'] != null)
                    _DetailRow(
                      label: 'Equipment stock available',
                      value:
                          '${item['available_quantity'] ?? 0} / ${item['total_quantity']} units',
                    ),
                  if (status.toUpperCase() == 'UNDER_MAINTENANCE') ...[
                    const SizedBox(height: 12),
                    Text(
                      'This unit is unavailable for rental. Other healthy units of the same equipment remain available.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (maintenance is List && maintenance.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text('Unit maintenance history',
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ...maintenance.take(3).whereType<Map>().map((ticket) {
                      final repairCost = ticket['repair_cost'];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${recordReference(ticket, 'maintenance')} · ${maintenanceStageLabel(ticket)}',
                                style: theme.textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(ticket['reason']?.toString() ??
                                  'Equipment inspection'),
                              const SizedBox(height: 8),
                              _DetailRow(
                                  label: 'Assigned staff',
                                  value: ticket['assigned_name']?.toString() ??
                                      'Unassigned'),
                              _DetailRow(
                                  label: 'Target completion',
                                  value: ticket['target_date']?.toString() ??
                                      'Not scheduled'),
                              _DetailRow(
                                  label: 'Total repair cost',
                                  value: repairCost is num
                                      ? _money(repairCost)
                                      : 'Not recorded'),
                              if (ticket['details'] != null)
                                Text(ticket['details'].toString()),
                              TextButton.icon(
                                onPressed: () => _maintenance(
                                    ticketId: ticket['id'].toString()),
                                icon: const Icon(Icons.build_outlined),
                                label: const Text('Open maintenance ticket'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Text(
                      'Open a ticket to record repairs, photos and final inspection checks.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (item['is_active'] != false &&
                      ['AVAILABLE', 'UNDER_MAINTENANCE']
                          .contains(status.toUpperCase()) &&
                      (item['open_maintenance'] ?? 0) == 0 &&
                      !snapshot.hasError)
                    OutlinedButton.icon(
                      onPressed: () => _maintenance(),
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('Report issue for this unit'),
                    ),
                  if (item['description']?.toString().trim().isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    Text('Description',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    Text(item['description'].toString()),
                  ],
                  if (rates is List && rates.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Recent rate records',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 4),
                    ...rates.take(3).whereType<Map>().map((rate) {
                      final amount = rate['rental_rate'];
                      final kind = rate['rate_type']?.toString() ?? 'Rate';
                      return Text('$kind · ${_money(amount)}');
                    }),
                  ],
                  if (snapshot.hasError) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Showing the equipment summary. Could not load the latest details.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (_qrError.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_qrError,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loadingQr ? null : () => _printQr(item),
                      icon: _loadingQr
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.qr_code_2_rounded),
                      label: Text(_loadingQr
                          ? 'Preparing label…'
                          : 'View / print QR label'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFDF762D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use the web admin workspace to edit equipment details or pricing.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 126,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.available});
  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final color = available ? const Color(0xFF27805C) : const Color(0xFFAD681B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

String? _first(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String _prettyStatus(String value) => value
    .replaceAll('_', ' ')
    .toLowerCase()
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _money(dynamic value) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  if (amount == null) return 'Not set';
  final formatted = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return '₱$formatted';
}
