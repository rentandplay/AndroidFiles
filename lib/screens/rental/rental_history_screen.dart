import '../../widgets/liquid_glass.dart';
import '../../widgets/glass_app_bar.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import '../../widgets/mobile_controls.dart';
import '../auth/login_screen.dart';
import '../user/catalog_screen.dart';

class RentalHistoryScreen extends StatefulWidget {
  const RentalHistoryScreen(
      {super.key, this.isAdmin = false, this.onBrowse, this.api});
  final bool isAdmin;
  final VoidCallback? onBrowse;
  final MobileApiService? api;

  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  late Future<List<RentalModel>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _filter = 'All';
  bool _compactView = true;
  String? _nextCursor;
  bool _loadingMore = false;
  List<RentalModel> _loadedRecords = [];

  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _eventSubscription = _api.watchRentalEvents().listen((event) {
      if (!mounted) return;
      final type = (event['event'] ?? '').toString();
      if (type == 'ready' || type.endsWith('.changed')) {
        setState(() {
          _future = _load();
        });
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
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
      records = await _api.listRentals();
      _nextCursor = _api.nextRentalCursor;
    } else {
      final result = await _api.adminRequest('/records/rentals?limit=5');
      _nextCursor = result['nextCursor'] as String?;
      records = (result['records'] as List)
          .whereType<Map>()
          .map((row) => RentalModel.fromMap(Map<String, dynamic>.from(row),
              id: row['id'].toString()))
          .toList();
    }

    final history = widget.isAdmin
        ? records
        : records.where((rental) => !rental.isOpen).toList();
    history.sort((a, b) => b.startDate.compareTo(a.startDate));
    _loadedRecords = history;
    return history;
  }

  Future<void> _loadMore() async {
    if (_nextCursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final List<RentalModel> more;
      if (widget.isAdmin) {
        final result = await _api.adminRequest(
            '/records/rentals?${Uri(queryParameters: {
              'limit': '5',
              'cursor': _nextCursor!
            }).query}');
        _nextCursor = result['nextCursor'] as String?;
        more = (result['records'] as List)
            .whereType<Map>()
            .map((row) => RentalModel.fromMap(Map<String, dynamic>.from(row),
                id: row['id']?.toString()))
            .toList();
      } else {
        final page = await _api.listRentalHistoryPage(_nextCursor!);
        more = page.records;
        _nextCursor = page.nextCursor;
      }
      if (!mounted) return;
      setState(() {
        _loadedRecords = {
          for (final row in [..._loadedRecords, ...more]) row.rentalId: row
        }.values.where((row) => widget.isAdmin || !row.isOpen).toList();
        _future = Future.value(_loadedRecords);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
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
                    rental.displayReference,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child:
                          RentalStatusBadge(status: rental.normalizedStatus)),
                  const Divider(height: 28),
                  if (widget.isAdmin)
                    RentalValueRow('Customer', rental.customerName),
                  RentalValueRow(
                      rental.isRentAndPlayPickup
                          ? 'Pickup location'
                          : 'Delivery location',
                      rental.customerHandoffLocation),
                  RentalValueRow('Rental date', _date(rental.startDate)),
                  if (rental.dueDate.millisecondsSinceEpoch > 0)
                    RentalValueRow('Due', _date(rental.dueDate)),
                  if (rental.returnedDate != null)
                    RentalValueRow('Returned', _date(rental.returnedDate!)),
                  RentalValueRow('Rental fee', rentalMoney(rental.rateFee)),
                  RentalValueRow('Payment', _paymentLabel(rental)),
                  if (rental.balanceDue > 0)
                    RentalValueRow(
                        'Balance due', rentalMoney(rental.balanceDue)),
                  if (rental.refundDue > 0)
                    RentalValueRow('Refund due', rentalMoney(rental.refundDue)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _historyCard(RentalModel rental) {
    if (_compactView && !widget.isAdmin) return _compactHistoryCard(rental);
    final code = rental.displayReference;
    final attention = _needsAttention(rental);
    final scheme = Theme.of(context).colorScheme;
    final stackedStatus = MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(16) > 19;
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
                  if (!stackedStatus) ...[
                    const SizedBox(width: 8),
                    RentalStatusBadge(status: rental.normalizedStatus),
                  ],
                ],
              ),
              if (stackedStatus) ...[
                const SizedBox(height: 10),
                Align(
                    alignment: Alignment.centerLeft,
                    child: RentalStatusBadge(status: rental.normalizedStatus)),
              ],
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
                ],
              ),
              if (rental.refundDue > 0 || rental.balanceDue > 0) ...[
                const SizedBox(height: 8),
                _settlementSummary(rental),
              ],
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

  Widget _compactHistoryCard(RentalModel rental) {
    final scheme = Theme.of(context).colorScheme;
    final day = DateFormat('MMM d, yyyy')
        .format(rental.startDate.toUtc().add(const Duration(hours: 8)));
    return Card(
      key: ValueKey('history-compact-${rental.rentalId}'),
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(rental),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primary.withValues(alpha: .09),
                child: Icon(Icons.receipt_long_outlined,
                    color: scheme.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rental.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('${rental.displayReference} · $day',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          color: scheme.onSurfaceVariant)),
                ],
              )),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant, size: 20),
            ]),
            const SizedBox(height: 9),
            Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RentalStatusBadge(status: rental.normalizedStatus),
                  Text('Fee ${rentalMoney(rental.rateFee)}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                ]),
            if (_needsAttention(rental)) ...[
              const SizedBox(height: 7),
              if (rental.balanceDue > 0 || rental.refundDue > 0)
                _settlementSummary(rental)
              else
                Text(_paymentLabel(rental),
                    style: TextStyle(
                        color: scheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _settlementSummary(RentalModel rental) {
    final scheme = Theme.of(context).colorScheme;
    Widget amount(String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(7)),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        );
    return Wrap(spacing: 8, runSpacing: 6, children: [
      if (rental.balanceDue > 0)
        amount('Due ${rentalMoney(rental.balanceDue)}', scheme.error),
      if (rental.refundDue > 0)
        amount('Refund ${rentalMoney(rental.refundDue)}', scheme.primary),
    ]);
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
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ],
      );

  Widget _viewToggle() => SizedBox(
      width: 48,
      height: 48,
      child: IconButton.filledTonal(
        key: const ValueKey('history-view-toggle'),
        tooltip: _compactView ? 'Show detailed view' : 'Show compact view',
        isSelected: _compactView,
        icon: const Icon(Icons.view_agenda_outlined),
        selectedIcon: const Icon(Icons.view_list_rounded),
        iconSize: 20,
        style: IconButton.styleFrom(
          foregroundColor: mobileAccentText(context),
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: .09),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => setState(() => _compactView = !_compactView),
      ));

  @override
  Widget build(BuildContext context) {
    final isSignedIn = Provider.of<AuthService>(context).currentUser != null;
    return Scaffold(
      appBar: GlassAppBar(
        titleText: widget.isAdmin ? 'All Transactions' : 'Rental History',
        actions: [
          if (!widget.isAdmin)
            HeaderActionPod(
              icon: _compactView
                  ? Icons.view_agenda_outlined
                  : Icons.view_headline_rounded,
              tooltip: _compactView ? 'Standard view' : 'Compact view',
              onTap: () => setState(() => _compactView = !_compactView),
            ),
          HeaderActionPod(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh history',
            onTap: _refresh,
          ),
          if (isSignedIn && !widget.isAdmin) const RentalNotificationBellPod(),
        ],
      ),
      body: LiquidAmbientBackdrop(
        child: !widget.isAdmin && !isSignedIn
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
                    if (_nextCursor != null)
                      OutlinedButton(
                          onPressed: _loadingMore ? null : _loadMore,
                          child: Text(_loadingMore
                              ? 'Loading…'
                              : 'Load more stored history')),
                    if (!widget.isAdmin) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Row(children: [
                          Expanded(
                              child: MobileSearchField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            hintText: 'Search rentals',
                          )),
                          const SizedBox(width: 8),
                          _viewToggle()
                        ]),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                        child: Row(
                          children: [
                            for (final filter in filters)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: MobileFilterChip(
                                  label: '$filter (${_count(records, filter)})',
                                  selected: filter == _filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                visible.length == records.length
                                    ? '${records.length} record${records.length == 1 ? '' : 's'}'
                                    : '${visible.length} of ${records.length} records',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant))),
                      ),
                    ],
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: visible.isEmpty
                            ? ListView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
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
                                            label:
                                                const Text('Browse equipment'),
                                          )
                                        : TextButton(
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() {
                                                _query = '';
                                                _filter = 'All';
                                              });
                                            },
                                            child: const Text(
                                                'Clear search and filters'),
                                          ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: visible.length,
                                itemBuilder: (context, index) =>
                                    _historyCard(visible[index]),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ),
    );
  }
}
