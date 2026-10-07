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
  const ActiveRentalsScreen({super.key, this.onBrowse});
  final VoidCallback? onBrowse;
  @override
  State<ActiveRentalsScreen> createState() => _ActiveRentalsScreenState();
}

class _ActiveRentalsScreenState extends State<ActiveRentalsScreen> {
  List<RentalModel>? _rentals;
  Timer? _poll;
  bool _refreshing = false;
  String _error = '';
  final _cancelling = <String>{};
  final _uploadingProof = <String>{};
  @override
  void initState() {
    super.initState();
    _refreshRentals();
    _poll =
        Timer.periodic(const Duration(seconds: 20), (_) => _refreshRentals());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refreshRentals() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final next = await MobileApiService.instance.listRentals();
      if (mounted)
        setState(() {
          _rentals = next;
          _error = '';
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _refreshing = false;
    }
  }

  void _openBrowse() {
    widget.onBrowse?.call();
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
      await MobileApiService.instance.cancelRental(rental.rentalId);
      if (mounted) await _refreshRentals();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
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
      await MobileApiService.instance.submitPaymentProof(
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
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _uploadingProof.remove(rental.rentalId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final open = (_rentals ?? []).where((rental) => rental.isOpen).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
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
                          _RentalListHeader(count: open.length),
                          const SizedBox(height: 8),
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
                        for (final rental in open)
                          RentalBookingCard(
                            rental: rental,
                            onTicket: () =>
                                TransactionTicketDialog.show(context, rental),
                            onUploadPaymentProof:
                                _uploadingProof.contains(rental.rentalId)
                                    ? null
                                    : () => _uploadPaymentProof(rental),
                            onCancel: _cancelling.contains(rental.rentalId)
                                ? null
                                : () => _cancelBooking(rental),
                            onReturn: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => ReturnEquipmentScreen(
                                          rental: rental)));
                              if (mounted) _refreshRentals();
                            },
                            onRefresh: _refreshRentals,
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
    if (rental.isAwaitingInspection) return 3;
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
                            ? 'Ready for handoff'
                            : 'Approved · preparing handoff',
                        rental.deliveryStatus == 'PREPARED'
                            ? 'Go to ${rental.deliveryLocation} and show your rental QR and a valid ID.'
                            : 'The operator is preparing your item for ${rental.deliveryLocation}. Your rental timer has not started.'
                      )
                    : rental.isActive && rental.hasPendingReturnRequest
                        ? (
                            overdue
                                ? 'Return request sent · overdue'
                                : 'Return request sent',
                            'Bring the equipment to the admin. Your rental timer stops when they receive it.'
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
                                    'The admin is checking the equipment and final charges. No action is needed right now.'
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
            Text(
                rental.rentalCode.isEmpty ? rental.rentalId : rental.rentalCode,
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
          (rental.isActive && !rental.hasPendingReturnRequest)) ...[
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
        else if (rental.isAwaitingPickup)
          FilledButton.icon(
              onPressed: onTicket,
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Show handoff QR'))
        else
          FilledButton.icon(
              onPressed: onReturn,
              icon: const Icon(Icons.assignment_return_rounded),
              label: const Text('Start return')),
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
            label: 'Pickup location',
            value: rental.deliveryLocation),
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
          const SizedBox(width: 12),
          amount('Security deposit', rentalMoney(rental.deposit)),
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
  const _RentalListHeader({required this.count});
  final int count;

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
            const SizedBox(height: 2),
            Text('Track each rental from request to return',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
            Text('UP NEXT',
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    letterSpacing: .7,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
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
  static const _labels = ['Request', 'Handoff', 'In use', 'Return'];

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
      required this.active,
      required this.track,
      required this.surface});
  final int step;
  final Color active, track, surface;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 5.5;
    final centerY = size.height / 2;
    final startX = radius;
    final endX = size.width - radius;
    final spacing = (endX - startX) / 3;
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
    for (var index = 0; index < 4; index++) {
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
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.surface != surface;
}
