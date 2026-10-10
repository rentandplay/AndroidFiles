import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import '../auth/login_screen.dart';
import '../user/catalog_screen.dart';

class RentalHistoryScreen extends StatefulWidget {
  const RentalHistoryScreen({super.key, this.isAdmin = false, this.onBrowse});
  final bool isAdmin;
  final VoidCallback? onBrowse;

  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  late Future<List<RentalModel>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<RentalModel>> _load() async {
    if (!widget.isAdmin &&
        Provider.of<AuthService>(context, listen: false).currentUser == null) {
      return [];
    }

    final List<RentalModel> records;
    if (!widget.isAdmin) {
      records = await MobileApiService.instance.listRentals();
    } else {
      final result = await MobileApiService.instance.adminRequest('/workspace');
      records = (result['transactions'] as List)
          .whereType<Map>()
          .map((row) => RentalModel.fromMap(Map<String, dynamic>.from(row),
              id: row['id'].toString()))
          .toList();
    }

    final history = widget.isAdmin
        ? records
        : records.where((rental) => !rental.isOpen).toList();
    history.sort((a, b) => b.startDate.compareTo(a.startDate));
    return history;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {}
  }

  bool _needsAttention(RentalModel rental) =>
      rental.balanceDue > 0 ||
      rental.refundDue > 0 ||
      rental.paymentStatus.toUpperCase().contains('PENDING');

  bool _matchesFilter(String filter, RentalModel rental) => switch (filter) {
        'Returned' => rental.normalizedStatus == 'COMPLETED',
        'Needs attention' => _needsAttention(rental),
        _ => true,
      };

  List<RentalModel> _visible(List<RentalModel> records) {
    final query = _query.trim().toLowerCase();
    return records.where((rental) {
      if (!_matchesFilter(_filter, rental)) return false;
      if (query.isEmpty) return true;
      return '${rental.itemName} ${rental.rentalCode} ${rental.rentalId} ${rental.statusLabel}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  int _count(List<RentalModel> records, String filter) =>
      records.where((rental) => _matchesFilter(filter, rental)).length;

  String _date(DateTime date) => DateFormat('MMM d, yyyy · h:mm a')
      .format(date.toUtc().add(const Duration(hours: 8)));

  String _paymentLabel(RentalModel rental) {
    final status = rental.paymentStatus.trim();
    if (status.isEmpty) return rental.paymentMethod;
    if (status.toUpperCase() == 'REFUND_PENDING') return 'Refund pending';
    return status
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  void _openBrowse() {
    if (widget.onBrowse != null) {
      widget.onBrowse!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CatalogScreen()),
    );
  }

  Future<void> _showDetails(RentalModel rental) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(rental.itemName,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    rental.rentalCode.isNotEmpty
                        ? rental.rentalCode
                        : rental.rentalId,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: RentalStatusBadge(status: rental.normalizedStatus)),
                  const Divider(height: 28),
                  if (widget.isAdmin)
                    RentalValueRow('Customer', rental.customerName),
                  RentalValueRow(
                      rental.isRentAndPlayPickup ? 'Kunin sa' : 'Ihahatid sa',
                      rental.customerHandoffLocation),
                  RentalValueRow('Rental date', _date(rental.startDate)),
                  if (rental.dueDate.millisecondsSinceEpoch > 0)
                    RentalValueRow('Due', _date(rental.dueDate)),
                  if (rental.returnedDate != null)
                    RentalValueRow('Returned', _date(rental.returnedDate!)),
                  RentalValueRow('Rental fee', rentalMoney(rental.rateFee)),
                  RentalValueRow('Payment', _paymentLabel(rental)),
                  if (rental.balanceDue > 0)
                    RentalValueRow('Balance due', rentalMoney(rental.balanceDue)),
                  if (rental.refundDue > 0)
                    RentalValueRow('Refund due', rentalMoney(rental.refundDue)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _historyCard(RentalModel rental) {
    final code = rental.rentalCode.isNotEmpty
        ? rental.rentalCode
        : rental.rentalId;
    final attention = _needsAttention(rental);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(rental),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary.withValues(alpha: .1),
                    child: Icon(Icons.sports_outlined,
                        color: scheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rental.itemName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  RentalStatusBadge(status: rental.normalizedStatus),
                ],
              ),
              const Divider(height: 26),
              Text('Rental date · ${_date(rental.startDate)}',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _amountSummary(
                        'Rental fee', rentalMoney(rental.rateFee)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    attention ? Icons.info_outline : Icons.payments_outlined,
                    size: 17,
                    color: attention ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      attention
                          ? _paymentLabel(rental)
                          : 'Payment · ${_paymentLabel(rental)}',
                      style: TextStyle(
                        color: attention
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (rental.refundDue > 0)
                    Text('Refund ${rentalMoney(rental.refundDue)}',
                        style: TextStyle(
                            color: scheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  if (rental.balanceDue > 0)
                    Text('Due ${rentalMoney(rental.balanceDue)}',
                        style: TextStyle(
                            color: scheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text('View details  ›',
                    style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountSummary(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isSignedIn = Provider.of<AuthService>(context).currentUser != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'All transactions' : 'Rental history'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh history',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !widget.isAdmin && !isSignedIn
          ? RentalEmptyState(
              title: 'Sign in to view your history',
              message:
                  'Your completed rentals and payment records will be saved here.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in'),
              ),
            )
          : FutureBuilder<List<RentalModel>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return RentalEmptyState(
                    title: 'Could not load rental history',
                    message: 'Check your connection and try again.',
                    action: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                  );
                }

                final records = snapshot.data ?? [];
                final visible = _visible(records);
                const filters = ['All', 'Returned', 'Needs attention'];
                return Column(
                  children: [
                    if (!widget.isAdmin) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _query = value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search item or rental ID',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${records.length} record${records.length == 1 ? '' : 's'}',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Row(
                          children: [
                            for (final filter in filters)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: FilterChip(
                                  label: Text(
                                      '$filter (${_count(records, filter)})'),
                                  selected: filter == _filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: [
                                  RentalEmptyState(
                                    title: records.isEmpty
                                        ? 'Your rental history starts here'
                                        : 'No matching records',
                                    message: records.isEmpty
                                        ? 'Once a rental request is closed, its status and payment details will appear here.'
                                        : 'Try another search or filter to find a record.',
                                    action: records.isEmpty
                                        ? FilledButton.icon(
                                            onPressed: _openBrowse,
                                            icon: const Icon(
                                                Icons.storefront_outlined),
                                            label: const Text('Browse equipment'),
                                          )
                                        : TextButton(
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() {
                                                _query = '';
                                                _filter = 'All';
                                              });
                                            },
                                            child: const Text('Clear search and filters'),
                                          ),
                                  ),
                                ],
                              )
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                children: [
                                  for (final rental in visible)
                                    _historyCard(rental),
                                ],
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
