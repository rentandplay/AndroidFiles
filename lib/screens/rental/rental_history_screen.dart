import '../../widgets/liquid_glass.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/premium_animations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../services/rental_receipt.dart';
import '../../widgets/rental_ui.dart';
import '../../widgets/mobile_controls.dart';
import '../../utils/error_sanitizer.dart';
import 'package:printing/printing.dart';
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
            .showSnackBar(SnackBar(content: Text(ErrorSanitizer.format(error))));
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

  Future<void> _showDetails(RentalModel rental) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showFrostedModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header: Equipment Icon, Item Name, Reference Code & Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.20),
                      ),
                    ),
                    child: Icon(
                      Icons.sports_tennis_rounded,
                      color: scheme.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rental.itemName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                rental.displayReference,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            RentalStatusBadge(status: rental.normalizedStatus),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Digital Receipt / Highlight Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            const Color(0xFF1E2D44).withValues(alpha: 0.65),
                            const Color(0xFF142032).withValues(alpha: 0.75),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.95),
                            const Color(0xFFF8FAFC).withValues(alpha: 0.90),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.25)
                          : const Color(0xFF64748B).withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rental Fee',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          rentalMoney(rental.rateFee),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: isDark
                                ? const Color(0xFFF0AD7C)
                                : const Color(0xFFDF762D),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.payments_outlined,
                            size: 15,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _paymentLabel(rental),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (rental.balanceDue > 0 || rental.refundDue > 0) ...[
                const SizedBox(height: 10),
                _settlementSummary(rental),
              ],

              const SizedBox(height: 16),

              // Section 1: Handoff & Timeline
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF162235).withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Handoff & Schedule',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (widget.isAdmin)
                      RentalValueRow('Customer', rental.customerName),
                    RentalValueRow(
                      rental.isRentAndPlayPickup
                          ? 'Pickup location'
                          : 'Delivery location',
                      rental.customerHandoffLocation,
                    ),
                    RentalValueRow('Rental date', _date(rental.startDate)),
                    if (rental.dueDate.millisecondsSinceEpoch > 0)
                      RentalValueRow('Due', _date(rental.dueDate)),
                    if (rental.returnedDate != null)
                      RentalValueRow('Returned', _date(rental.returnedDate!)),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Section 2: Financial Breakdown
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF162235).withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Financial Summary',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    RentalValueRow('Rental fee', rentalMoney(rental.rateFee)),
                    if (rental.overtimeFee != null && rental.overtimeFee! > 0)
                      RentalValueRow(
                          'Late charges', rentalMoney(rental.overtimeFee!)),
                    if (rental.penaltyAmount != null &&
                        rental.penaltyAmount! > 0)
                      RentalValueRow('Damage / missing penalty',
                          rentalMoney(rental.penaltyAmount!)),
                    if (rental.finalRentalCharges != null)
                      RentalValueRow('Final total',
                          rentalMoney(rental.finalRentalCharges!),
                          emphasis: true),
                    RentalValueRow('Payment', _paymentLabel(rental)),
                    if (rental.balanceDue > 0)
                      RentalValueRow(
                          'Balance due', rentalMoney(rental.balanceDue),
                          emphasis: true),
                    if (rental.refundDue > 0)
                      RentalValueRow(
                          'Refund due', rentalMoney(rental.refundDue),
                          emphasis: true),
                  ],
                ),
              ),

              if (rental.normalizedStatus == 'COMPLETED') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ref = rental.rentalCode.trim().isNotEmpty
                          ? rental.rentalCode.trim()
                          : rental.rentalId;
                      try {
                        await Printing.layoutPdf(
                          name: 'Rental-$ref.pdf',
                          onLayout: (_) =>
                              buildRentalReceipt(rental.toReceiptMap()),
                        );
                      } catch (error) {
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Could not open receipt PDF: $error')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Print / Save receipt PDF'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Dismiss / Close Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Close',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyCard(RentalModel rental) {
    if (widget.isAdmin) return _detailedHistoryCard(rental);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          child: child,
        ),
      ),
      child: _compactView
          ? _compactHistoryCard(rental)
          : _detailedHistoryCard(rental),
    );
  }

  Widget _detailedHistoryCard(RentalModel rental) {
    final code = rental.displayReference;
    final attention = _needsAttention(rental);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stackedStatus = MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(16) > 19;
    return GlassCard(
      key: ValueKey('history-detailed-${rental.rentalId}'),
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      onTap: () => _showDetails(rental),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18),
                  ),
                ),
                child: Icon(Icons.sports_tennis_rounded,
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          Text('Rental date · ${_date(rental.startDate)}',
              style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child:
                    _amountSummary('Rental fee', rentalMoney(rental.rateFee)),
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
                    color: attention ? scheme.primary : scheme.onSurfaceVariant,
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
          const SizedBox(height: 6),
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
    );
  }

  Widget _compactHistoryCard(RentalModel rental) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final day = DateFormat('MMM d, yyyy')
        .format(rental.startDate.toUtc().add(const Duration(hours: 8)));
    return GlassCard(
      key: ValueKey('history-compact-${rental.rentalId}'),
      margin: const EdgeInsets.only(bottom: 10),
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => _showDetails(rental),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18),
              ),
            ),
            child: Icon(Icons.sports_tennis_rounded,
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
              const SizedBox(height: 2),
              Text('${rental.displayReference} · $day',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: scheme.onSurfaceVariant)),
            ],
          )),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6), size: 20),
        ]),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 4,
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
          const SizedBox(height: 6),
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
    );
  }

  Widget _settlementSummary(RentalModel rental) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget amount(String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.24))),
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
        icon: const AnimatedRotation(
          duration: Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          turns: 0.5,
          child: Icon(Icons.view_agenda_outlined),
        ),
        selectedIcon: const AnimatedRotation(
          duration: Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          turns: 0.0,
          child: Icon(Icons.view_list_rounded),
        ),
        iconSize: 20,
        style: IconButton.styleFrom(
          foregroundColor: mobileAccentText(context),
          backgroundColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: .09),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () {
          HapticFeedback.selectionClick();
          setState(() => _compactView = !_compactView);
        },
      ));

  @override
  Widget build(BuildContext context) {
    final isSignedIn = Provider.of<AuthService>(context).currentUser != null;
    return Scaffold(
      appBar: GlassAppBar(
        titleText: widget.isAdmin ? 'All Transactions' : 'Rental History',
        actions: [
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
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
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
                                  if (_nextCursor != null) ...[
                                    const SizedBox(height: 16),
                                    Center(
                                      child: OutlinedButton(
                                        onPressed:
                                            _loadingMore ? null : _loadMore,
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Text(_loadingMore
                                            ? 'Loading…'
                                            : 'Load more stored history'),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : ListView.builder(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: visible.length +
                                    (_nextCursor != null ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= visible.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                          top: 8, bottom: 16),
                                      child: Center(
                                        child: OutlinedButton(
                                          onPressed:
                                              _loadingMore ? null : _loadMore,
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: Text(
                                            _loadingMore
                                                ? 'Loading…'
                                                : 'Load more stored history',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return StaggeredSlideFade(
                                    index: index,
                                    child: _historyCard(visible[index]),
                                  );
                                },
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
