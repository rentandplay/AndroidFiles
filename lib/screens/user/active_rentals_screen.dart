import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/item_model.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/rental_ui.dart';
import '../auth/login_screen.dart';
import '../shared/transaction_ticket_dialog.dart';
import 'return_equipment_screen.dart';

class ActiveRentalsScreen extends StatefulWidget {
  const ActiveRentalsScreen(
      {super.key, this.onBrowse, this.isActive = true, this.api});
  final VoidCallback? onBrowse;
  final bool isActive;
  final MobileApiService? api;
  @override
  State<ActiveRentalsScreen> createState() => _ActiveRentalsScreenState();
}

class _ActiveRentalsScreenState extends State<ActiveRentalsScreen>
    with WidgetsBindingObserver {
  List<RentalModel>? _rentals;
  StreamSubscription<Map<String, dynamic>>? _rentalEvents;
  Timer? _rentalClock;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _appResumed = true;
  String? _eventUid;
  String _error = '';
  String _rentalFilter = 'All';
  String _rentalQuery = '';
  final _cancelling = <String>{};
  final _uploadingProof = <String>{};
  MobileApiService get _api => widget.api ?? MobileApiService.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncRentalClock();
  }

  @override
  void didUpdateWidget(covariant ActiveRentalsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncRentalEvents();
      _syncRentalClock();
      if (widget.isActive) _refreshRentals();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<AuthService>().currentUser?.uid;
    if (_eventUid != uid) {
      _eventUid = uid;
      _syncRentalEvents();
      if (uid != null) _refreshRentals();
    }
  }

  void _syncRentalEvents() {
    _rentalEvents?.cancel();
    _rentalEvents = null;
    if (!widget.isActive || !_appResumed || _eventUid == null) return;
    _rentalEvents = _api.watchRentalEvents().listen((event) {
      if (!mounted) return;
      if (event['event'] == 'rental.changed') {
        _refreshRentals();
      } else if (event['event'] == 'ready') {
        _refreshRentals();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncRentalEvents();
    _syncRentalClock();
    if (_appResumed && widget.isActive) _refreshRentals();
  }

  void _syncRentalClock() {
    _rentalClock?.cancel();
    _rentalClock = null;
    if (!widget.isActive ||
        !_appResumed ||
        !(_rentals ?? const <RentalModel>[]).any((rental) => rental.isActive)) {
      return;
    }
    _rentalClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rentalEvents?.cancel();
    _rentalClock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshRentals() async {
    if (!mounted) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final next = await _api.listRentals();
      if (mounted) {
        setState(() {
          _rentals = next;
          _error = '';
        });
        _syncRentalClock();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _refreshing = false;
      if (_refreshAgain &&
          mounted &&
          widget.isActive &&
          _appResumed &&
          _eventUid != null) {
        _refreshAgain = false;
        unawaited(_refreshRentals());
      }
    }
  }

  void _openBrowse() {
    widget.onBrowse?.call();
  }

  bool _holdEnded(RentalModel rental, DateTime now) =>
      rental.canCancel &&
      rental.holdExpiresAt != null &&
      now.isAfter(rental.holdExpiresAt!);

  bool _isOverdue(RentalModel rental, DateTime now) =>
      rental.isActive &&
      rental.dueDate.millisecondsSinceEpoch > 0 &&
      now.isAfter(rental.dueDate);

  bool _isDueSoon(RentalModel rental, DateTime now) {
    if (!rental.isActive || rental.dueDate.millisecondsSinceEpoch <= 0) {
      return false;
    }
    final remaining = rental.dueDate.difference(now);
    return !remaining.isNegative && remaining <= const Duration(hours: 24);
  }

  bool _isReturning(RentalModel rental) =>
      rental.hasPendingReturnRequest ||
      rental.isAwaitingInspection ||
      (rental.isPendingVerification &&
          rental.normalizedStatus.contains('RETURN'));

  bool _matchesRentalFilter(RentalModel rental, DateTime now) =>
      switch (_rentalFilter) {
        'Needs attention' => _holdEnded(rental, now) ||
            _isOverdue(rental, now) ||
            _isDueSoon(rental, now) ||
            rental.hasPendingReturnRequest ||
            (rental.paymentMethod.toUpperCase() == 'QR' &&
                rental.paymentProofStatus == 'REJECTED'),
        'Pickup' => rental.isAwaitingPickup,
        'In use' => rental.isActive && !rental.hasPendingReturnRequest,
        'Returning' => _isReturning(rental),
        _ => true,
      };

  int _rentalPriority(RentalModel rental, DateTime now) {
    if (_isOverdue(rental, now)) return 0;
    if (rental.hasPendingReturnRequest) return 1;
    if (_holdEnded(rental, now) ||
        (rental.paymentMethod.toUpperCase() == 'QR' &&
            rental.paymentProofStatus == 'REJECTED')) {
      return 2;
    }
    if (rental.isAwaitingPickup &&
        rental.deliveryStatus.toUpperCase() == 'PREPARED') {
      return 3;
    }
    if (rental.isAwaitingPickup) return 4;
    if (rental.isActive && rental.dueDate.millisecondsSinceEpoch > 0) {
      final remaining = rental.dueDate.difference(now);
      if (!remaining.isNegative && remaining <= const Duration(hours: 24)) {
        return 5;
      }
    }
    if (rental.isActive) return 6;
    if (rental.isAwaitingInspection) return 7;
    if (rental.isPendingAdminReview) return 8;
    return 9;
  }

  Future<void> _cancelBooking(RentalModel rental) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Cancel this rental request?'),
              content: const Text(
                  'The equipment hold will be released. Any verified payment remains recorded for refund.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Keep request')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Cancel request')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling.add(rental.rentalId));
    try {
      await _api.cancelRental(rental.rentalId);
      if (mounted) await _refreshRentals();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _cancelling.remove(rental.rentalId));
    }
  }

  Future<void> _uploadPaymentProof(RentalModel rental) async {
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1800, imageQuality: 75);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 350000) {
        throw const MobileApiException('Choose a screenshot under 350 KB.');
      }
      final isPng = bytes.length >= 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71;
      final isJpeg = bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      if (!isPng && !isJpeg) {
        throw const MobileApiException('Choose a PNG or JPEG screenshot.');
      }
      setState(() => _uploadingProof.add(rental.rentalId));
      await _api.submitPaymentProof(
          rentalId: rental.rentalId,
          imageDataUrl:
              'data:image/${isPng ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}',
          reference: rental.paymentProofReference);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment screenshot sent for owner review.')));
        await _refreshRentals();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _uploadingProof.remove(rental.rentalId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final now = DateTime.now();
    final open = (_rentals ?? []).where((rental) => rental.isOpen).toList()
      ..sort((a, b) {
        final priority =
            _rentalPriority(a, now).compareTo(_rentalPriority(b, now));
        if (priority != 0) return priority;
        final aDue = a.dueDate.millisecondsSinceEpoch > 0
            ? a.dueDate.millisecondsSinceEpoch
            : 0;
        final bDue = b.dueDate.millisecondsSinceEpoch > 0
            ? b.dueDate.millisecondsSinceEpoch
            : 0;
        if (aDue != bDue && aDue > 0 && bDue > 0) return aDue.compareTo(bDue);
        return b.startDate.compareTo(a.startDate);
      });
    final query = _rentalQuery.trim().toLowerCase();
    final visible = open
        .where((rental) => _matchesRentalFilter(rental, now))
        .where((rental) =>
            query.isEmpty ||
            [
              rental.itemName,
              rental.rentalCode,
              rental.rentalId,
              rental.itemId,
            ].any((value) => value.toLowerCase().contains(query)))
        .toList();
    final overdueCount = open.where((rental) => _isOverdue(rental, now)).length;
    final dueSoonCount = open.where((rental) => _isDueSoon(rental, now)).length;
    final returnCount = open.where(_isReturning).length;
    final attentionCount = open
        .where((rental) =>
            _holdEnded(rental, now) ||
            _isOverdue(rental, now) ||
            _isDueSoon(rental, now) ||
            rental.hasPendingReturnRequest ||
            (rental.paymentMethod.toUpperCase() == 'QR' &&
                rental.paymentProofStatus == 'REJECTED'))
        .length;
    final filterCounts = <String, int>{
      'All': open.length,
      'Needs attention': attentionCount,
      'Pickup': open.where((rental) => rental.isAwaitingPickup).length,
      'In use': open
          .where((rental) => rental.isActive && !rental.hasPendingReturnRequest)
          .length,
      'Returning': returnCount,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('My Rentals'), actions: [
        IconButton(
            tooltip: 'Refresh rentals',
            onPressed: _refreshRentals,
            icon: const Icon(Icons.refresh)),
      ]),
      body: user == null
          ? RentalEmptyState(
              title: 'Sign in to view rentals',
              message:
                  'Your rental requests and equipment in use will appear here.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign in'),
              ),
            )
          : _rentals == null && _error.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _refreshRentals,
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_error.isNotEmpty) ...[
                          RentalNotice(
                              isError: true,
                              title: _rentals == null
                                  ? 'Could not load rentals'
                                  : 'Could not refresh rentals',
                              message: _rentals == null
                                  ? _error
                                  : 'Showing your last loaded records. Pull down to retry.',
                              action: TextButton(
                                  onPressed: _refreshRentals,
                                  child: const Text('Try again'))),
                          const SizedBox(height: 16),
                        ],
                        if (open.isNotEmpty) ...[
                          _RentalListHeader(
                              count: open.length,
                              overdueCount: overdueCount,
                              dueSoonCount: dueSoonCount,
                              returningCount: returnCount),
                          const SizedBox(height: 8),
                        ],
                        if (open.length > 1) ...[
                          if (open.length > 3) ...[
                            TextField(
                                key: const ValueKey('rental-search'),
                                onChanged: (value) =>
                                    setState(() => _rentalQuery = value),
                                decoration: InputDecoration(
                                    hintText: 'Search item or rental code',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _rentalQuery.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            onPressed: () => setState(() {
                                                  _rentalQuery = '';
                                                }),
                                            icon: const Icon(Icons.close)),
                                    border: const OutlineInputBorder())),
                            const SizedBox(height: 10),
                          ],
                          SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                for (final entry in filterCounts.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                        label: Text(
                                            '${entry.key} · ${entry.value}'),
                                        selected: _rentalFilter == entry.key,
                                        onSelected: (_) => setState(
                                            () => _rentalFilter = entry.key)),
                                  ),
                              ])),
                          if (visible.length != open.length) ...[
                            const SizedBox(height: 8),
                            Text(
                                'Showing ${visible.length} of ${open.length} rentals',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ],
                          const SizedBox(height: 12),
                        ],
                        if (open.isEmpty && _rentals != null)
                          RentalEmptyState(
                            title: 'No rentals in progress',
                            message:
                                'Your rental requests and equipment in use will appear here.',
                            action: widget.onBrowse == null
                                ? null
                                : FilledButton.icon(
                                    onPressed: _openBrowse,
                                    icon: const Icon(Icons.storefront_outlined),
                                    label: const Text('Browse equipment'),
                                  ),
                          ),
                        if (visible.isEmpty && open.isNotEmpty)
                          RentalEmptyState(
                              title: 'No rentals match this view',
                              message:
                                  'Try another filter or search for an item or rental code.',
                              action: TextButton(
                                  onPressed: () => setState(() {
                                        _rentalFilter = 'All';
                                        _rentalQuery = '';
                                      }),
                                  child: const Text('Clear filters'))),
                        for (final rental in visible)
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: RentalBookingCard(
                                key: ValueKey(rental.rentalId),
                                rental: rental,
                                onTicket: () => TransactionTicketDialog.show(
                                    context, rental),
                                onUploadPaymentProof:
                                    _uploadingProof.contains(rental.rentalId)
                                        ? null
                                        : () => _uploadPaymentProof(rental),
                                onCancel: _cancelling.contains(rental.rentalId)
                                    ? null
                                    : () => _cancelBooking(rental),
                                onReturn: () async {
                                  final isTrackingReturn =
                                      rental.hasPendingReturnRequest ||
                                          rental.isAwaitingInspection ||
                                          (rental.isPendingVerification &&
                                              rental.normalizedStatus
                                                  .contains('RETURN'));
                                  await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => isTrackingReturn
                                              ? RentalReturnStatusScreen(
                                                  rental: rental, api: _api)
                                              : ReturnEquipmentScreen(
                                                  rental: rental, api: _api)));
                                  if (mounted) _refreshRentals();
                                },
                                onRefresh: _refreshRentals,
                              ),
                            ),
                          ),
                      ]),
                ),
    );
  }
}

class RentalBookingCard extends StatelessWidget {
  const RentalBookingCard(
      {super.key,
      required this.rental,
      this.onTicket,
      this.onCancel,
      this.onReturn,
      this.onUploadPaymentProof,
      this.onRefresh});
  final RentalModel rental;
  final VoidCallback? onTicket,
      onCancel,
      onReturn,
      onRefresh,
      onUploadPaymentProof;
  String _date(DateTime value) =>
      DateFormat('MMM d · h:mm a').format(value.toLocal());

  int _progressStep() {
    if (rental.isAwaitingInspection) return 2;
    if (rental.isActive || rental.hasPendingReturnRequest) return 2;
    if (rental.isPendingVerification) {
      return rental.normalizedStatus.contains('RETURN') ? 2 : 1;
    }
    if (rental.isAwaitingPickup) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final holdEnded = rental.canCancel &&
        rental.holdExpiresAt != null &&
        now.isAfter(rental.holdExpiresAt!);
    final hasDueDate = rental.dueDate.millisecondsSinceEpoch > 0;
    final overdue =
        rental.isActive && hasDueDate && now.isAfter(rental.dueDate);
    final minutes = rental.dueDate.difference(now).inMinutes.abs();
    final time = minutes >= 60
        ? '${minutes ~/ 60}h ${minutes % 60}m'
        : '${minutes < 1 ? 1 : minutes}m';
    final paymentRejected = rental.paymentMethod.toUpperCase() == 'QR' &&
        rental.paymentProofStatus == 'REJECTED';
    final paymentUnderReview = rental.paymentMethod.toUpperCase() == 'QR' &&
        rental.paymentProofStatus == 'PENDING_REVIEW';
    final isRentAndPlayPickup = rental.isRentAndPlayPickup;
    final (heading, message) = paymentRejected
        ? (
            'Payment needs an update',
            rental.paymentProofNote.isEmpty
                ? 'The owner could not verify this screenshot. Upload a clear screenshot of the successful transfer.'
                : rental.paymentProofNote
          )
        : holdEnded
            ? (
                'Hold ended',
                'Refresh to check the latest status of this request.'
              )
            : rental.isPendingAdminReview
                ? (
                    'Waiting for owner review',
                    paymentUnderReview
                        ? 'Your payment screenshot is being checked. We’ll update this tracker when the review is complete.'
                        : 'Your request is being reviewed. The rental timer starts at handoff.'
                  )
                : rental.isAwaitingPickup
                    ? (
                        rental.deliveryStatus == 'PREPARED'
                            ? isRentAndPlayPickup
                                ? 'Ready at Rent & Play'
                                : 'Ready for delivery'
                            : isRentAndPlayPickup
                                ? 'Approved · preparing your item'
                                : 'Approved · preparing delivery',
                        rental.deliveryStatus == 'PREPARED'
                            ? isRentAndPlayPickup
                                ? 'Go to Rent & Play at ASRI and show your rental QR code and valid ID.'
                                : 'Ready for ${rental.deliveryLocation}. Show your rental QR code and valid ID at handoff.'
                            : isRentAndPlayPickup
                                ? 'Staff is preparing your item. Rental time starts at handoff.'
                                : 'Staff is preparing your item for ${rental.deliveryLocation}. Rental time has not started yet.'
                      )
                    : rental.isActive && rental.hasPendingReturnRequest
                        ? (
                            overdue
                                ? 'Return request sent · overdue'
                                : 'Return request sent',
                            overdue
                                ? 'Bring the equipment to the admin as soon as possible. Late charges are based on when the admin records physical receipt.'
                                : 'Your request is recorded. The rental stays active and the timer stops when the admin physically receives the equipment.'
                          )
                        : rental.isPendingVerification
                            ? rental.normalizedStatus.contains('RETURN')
                                ? (
                                    'Return awaiting confirmation',
                                    'Bring the equipment to the admin. The timer stops when they record receipt.'
                                  )
                                : (
                                    'Handoff awaiting confirmation',
                                    'The rental timer starts after the operator confirms the handoff.'
                                  )
                            : rental.isAwaitingInspection
                                ? (
                                    'Returned · inspection in progress',
                                    'The rental timer stopped when the admin recorded receipt. They will inspect the item and finalize any balance.'
                                  )
                                : rental.isActive
                                    ? (
                                        overdue
                                            ? 'Overdue by $time'
                                            : hasDueDate
                                                ? '$time remaining'
                                                : 'Return time not recorded',
                                        'Return the equipment to the admin before your due time.'
                                      )
                                    : (
                                        'Waiting for an update',
                                        'Pull down to refresh if you are waiting at the pickup location.'
                                      );
    final nextIcon = holdEnded || overdue
        ? Icons.schedule_rounded
        : rental.isPendingAdminReview || paymentRejected
            ? Icons.hourglass_top_rounded
            : rental.isAwaitingPickup
                ? Icons.qr_code_rounded
                : rental.isAwaitingInspection
                    ? Icons.fact_check_outlined
                    : rental.isActive
                        ? Icons.assignment_return_outlined
                        : Icons.sync_rounded;
    final alertColor = holdEnded || overdue || paymentRejected
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return RentalSection(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _RentalItemThumbnail(rental: rental),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rental.itemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(rental.displayReference,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            RentalStatusBadge(
                status: rental.hasPendingReturnRequest
                    ? 'RETURN_REQUESTED'
                    : rental.normalizedStatus),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      _RentalProgressTracker(step: _progressStep()),
      const SizedBox(height: 18),
      _RentalNextStep(
          title: heading, message: message, icon: nextIcon, color: alertColor),
      if (holdEnded ||
          paymentRejected ||
          rental.isAwaitingPickup ||
          rental.hasPendingReturnRequest ||
          rental.isAwaitingInspection ||
          rental.isActive) ...[
        const SizedBox(height: 14),
        if (holdEnded)
          OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh status'))
        else if (paymentRejected)
          FilledButton.icon(
              onPressed: onUploadPaymentProof,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Upload receipt'))
        else if (rental.isAwaitingPickup &&
            rental.deliveryStatus.toUpperCase() == 'PREPARED')
          FilledButton.icon(
              onPressed: onTicket,
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Show handoff QR'))
        else if (rental.hasPendingReturnRequest ||
            rental.isAwaitingInspection ||
            (rental.isPendingVerification &&
                rental.normalizedStatus.contains('RETURN')))
          OutlinedButton.icon(
              onPressed: onReturn,
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('View return status'))
        else if (rental.isActive && !rental.hasPendingReturnRequest)
          FilledButton.icon(
              onPressed: onReturn,
              icon: const Icon(Icons.assignment_return_rounded),
              label: const Text('Request return')),
      ],
      if (rental.canCancel)
        Align(
            alignment: Alignment.center,
            child: TextButton(
                onPressed: onCancel, child: const Text('Cancel request'))),
      const SizedBox(height: 8),
      if (rental.isAwaitingPickup || rental.isPendingAdminReview)
        _RentalDetailLine(
            icon: Icons.place_outlined,
            label: isRentAndPlayPickup ? 'Get your item at' : 'Delivery to',
            value: rental.customerHandoffLocation),
      if (rental.holdExpiresAt != null && rental.canCancel)
        _RentalDetailLine(
            icon: Icons.schedule_outlined,
            label: rental.isPendingAdminReview
                ? 'Review hold ends'
                : 'Handoff before',
            value: _date(rental.holdExpiresAt!)),
      if (rental.isActive)
        _RentalDetailLine(
            icon: Icons.schedule_outlined,
            label: 'Return by',
            value: hasDueDate ? _date(rental.dueDate) : 'Ask the admin',
            isUrgent: overdue),
      if (rental.receivedAt != null)
        _RentalDetailLine(
            icon: Icons.check_circle_outline_rounded,
            label: 'Received',
            value: _date(rental.receivedAt!)),
      const SizedBox(height: 8),
      _RentalPriceSummary(rental: rental),
    ]));
  }
}

class _RentalItemThumbnail extends StatelessWidget {
  const _RentalItemThumbnail({required this.rental});
  final RentalModel rental;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localItem = ItemModel.findByCode(rental.itemId) ??
        ItemModel.findByCode(rental.itemName);

    Widget fallback() =>
        localItem?.buildImage(
          fit: BoxFit.cover,
          width: 72,
          height: 72,
        ) ??
        Container(
          width: 72,
          height: 72,
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.sports_volleyball_outlined,
              color: scheme.onSurfaceVariant, size: 30),
        );

    final url = rental.itemImageUrl?.trim() ?? '';
    Widget image = fallback();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      image = Image.network(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback(),
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    } else if (url.startsWith('assets/')) {
      image = Image.asset(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    return Semantics(
      image: true,
      label: rental.itemName,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(width: 72, height: 72, child: image),
      ),
    );
  }
}

class _RentalDetailLine extends StatelessWidget {
  const _RentalDetailLine({
    required this.icon,
    required this.label,
    required this.value,
    this.isUrgent = false,
  });
  final IconData icon;
  final String label, value;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isUrgent ? scheme.error : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isUrgent ? scheme.error : scheme.onSurface)),
        ),
      ]),
    );
  }
}

class _RentalPriceSummary extends StatelessWidget {
  const _RentalPriceSummary({required this.rental});
  final RentalModel rental;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget amount(String label, String value) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Row(children: [
          amount('Rental fee', rentalMoney(rental.rateFee)),
        ]),
        if (rental.balanceDue > 0 && !rental.canCancel) ...[
          const SizedBox(height: 10),
          _RentalDetailLine(
              icon: Icons.payments_outlined,
              label: 'Balance due',
              value: rentalMoney(rental.balanceDue)),
        ],
        if (rental.refundDue > 0) ...[
          const SizedBox(height: 10),
          _RentalDetailLine(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Refund due',
              value: rentalMoney(rental.refundDue)),
        ],
      ]),
    );
  }
}

class _RentalListHeader extends StatelessWidget {
  const _RentalListHeader(
      {required this.count,
      required this.overdueCount,
      required this.dueSoonCount,
      required this.returningCount});
  final int count, overdueCount, dueSoonCount, returningCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.local_activity_outlined, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$count rental${count == 1 ? '' : 's'} in progress',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            if (overdueCount > 0 || dueSoonCount > 0 || returningCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                  [
                    if (overdueCount > 0) '$overdueCount overdue',
                    if (dueSoonCount > 0) '$dueSoonCount due soon',
                    if (returningCount > 0) '$returningCount returning',
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 12,
                      color: overdueCount > 0
                          ? scheme.error
                          : dueSoonCount > 0
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _RentalNextStep extends StatelessWidget {
  const _RentalNextStep({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  });
  final String title, message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border.all(color: color.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 3),
            Text(message,
                style: TextStyle(
                    color: scheme.onSurface, fontSize: 13, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class _RentalProgressTracker extends StatelessWidget {
  const _RentalProgressTracker({required this.step});
  final int step;
  static const _labels = ['Request', 'Handoff', 'In use'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = scheme.primary;
    final track = scheme.outline.withValues(alpha: .45);
    return Semantics(
      label: 'Rental progress: ${_labels[step]} stage',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 18,
          child: CustomPaint(
            painter: _RentalProgressPainter(
                step: step,
                stepCount: _labels.length,
                active: active,
                track: track,
                surface: scheme.surface),
          ),
        ),
        const SizedBox(height: 5),
        Row(children: [
          for (var index = 0; index < _labels.length; index++)
            Expanded(
              child: Text(_labels[index],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: index <= step ? active : scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight:
                        index == step ? FontWeight.w800 : FontWeight.w500,
                  )),
            ),
        ]),
      ]),
    );
  }
}

class _RentalProgressPainter extends CustomPainter {
  const _RentalProgressPainter(
      {required this.step,
      required this.stepCount,
      required this.active,
      required this.track,
      required this.surface});
  final int step, stepCount;
  final Color active, track, surface;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 5.5;
    final centerY = size.height / 2;
    final startX = radius;
    final endX = size.width - radius;
    final spacing = (endX - startX) / (stepCount - 1);
    final basePaint = Paint()
      ..color = track
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final activePaint = Paint()
      ..color = active
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(startX, centerY), Offset(endX, centerY), basePaint);
    if (step > 0) {
      canvas.drawLine(Offset(startX, centerY),
          Offset(startX + spacing * step, centerY), activePaint);
    }
    for (var index = 0; index < stepCount; index++) {
      final center = Offset(startX + spacing * index, centerY);
      if (index == step) {
        canvas.drawCircle(
            center,
            8,
            Paint()
              ..color = active.withValues(alpha: .16)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = active
              ..style = PaintingStyle.fill);
      } else {
        canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = index < step ? active : surface
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            center,
            radius,
            Paint()
              ..color = index < step ? active : track
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RentalProgressPainter oldDelegate) =>
      oldDelegate.step != step ||
      oldDelegate.stepCount != stepCount ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.surface != surface;
}
