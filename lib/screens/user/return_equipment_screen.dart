import '../../services/server_clock.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/rental_model.dart';
import '../../services/mobile_api_service.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rental_receipt_card.dart';
import '../../widgets/rental_ui.dart';
import 'customer_home_screen.dart';

class ReturnEquipmentScreen extends StatefulWidget {
  const ReturnEquipmentScreen({super.key, required this.rental, this.api});
  final RentalModel rental;
  final MobileApiService? api;
  @override
  State<ReturnEquipmentScreen> createState() => _ReturnEquipmentScreenState();
}

class _ReturnEquipmentScreenState extends State<ReturnEquipmentScreen> {
  String _selectedCondition = 'GOOD';
  final _notes = TextEditingController();
  bool _busy = false;
  String _error = '';
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await (widget.api ?? MobileApiService.instance).requestReturn(
          rentalId: widget.rental.rentalId,
          condition: _selectedCondition,
          notes: _notes.text.trim());
      if (!mounted) return;
      await Navigator.pushReplacement<void, void>(
          context,
          MaterialPageRoute(
              builder: (_) => RentalReturnStatusScreen(
                  rental: widget.rental.copyWith(
                      latestReturnRequestStatus: 'PENDING_ADMIN_APPROVAL'),
                  api: widget.api)));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: const GlassAppBar(titleText: 'Request return'),
          bottomNavigationBar: RentalActionBar(
              label: 'Send return request', onPressed: _submit, busy: _busy),
          body: LiquidAmbientBackdrop(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 712),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RentalSection(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(widget.rental.itemName,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(widget.rental.displayReference),
                              const Divider(height: 24),
                              RentalValueRow(
                                  'Return by',
                                  widget.rental.dueDate.millisecondsSinceEpoch >
                                          0
                                      ? DateFormat('MMM d · h:mm a').format(
                                          widget.rental.dueDate.toLocal())
                                      : 'Not recorded'),
                            ])),
                        RentalSection(
                          title: 'How is the equipment?',
                          icon: Icons.fact_check_outlined,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  for (final option in {
                                    'GOOD': 'Good',
                                    'NEEDS_INSPECTION': 'Needs checking',
                                    'DAMAGED': 'Damaged'
                                  }.entries)
                                    ChoiceChip(
                                        label: Text(option.value),
                                        selected:
                                            _selectedCondition == option.key,
                                        onSelected: _busy
                                            ? null
                                            : (_) => setState(() =>
                                                _selectedCondition =
                                                    option.key)),
                                ]),
                                const SizedBox(height: 18),
                                TextField(
                                    controller: _notes,
                                    enabled: !_busy,
                                    maxLines: 3,
                                    maxLength: 2000,
                                    decoration: const InputDecoration(
                                        labelText: 'Condition notes (optional)',
                                        hintText:
                                            'Tell us about scratches, damage or missing parts.')),
                              ]),
                        ),
                        const RentalNotice(
                            title: 'Return steps',
                            icon: Icons.assignment_return_outlined,
                            message:
                                'Send this request, then hand the item to the admin. Rental time stops at receipt while they inspect it.'),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          RentalNotice(
                              isError: true,
                              title: 'Could not send return request',
                              message: _error),
                        ],
                        const SizedBox(height: 16),
                      ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class RentalReturnStatusScreen extends StatefulWidget {
  const RentalReturnStatusScreen({
    super.key,
    required this.rental,
    this.api,
    this.onPrintOrSavePdf,
    this.onSharePdf,
    this.onDone,
  });
  final RentalModel rental;
  final MobileApiService? api;
  final ReceiptPdfAction? onPrintOrSavePdf;
  final ReceiptPdfAction? onSharePdf;
  final VoidCallback? onDone;

  @override
  State<RentalReturnStatusScreen> createState() =>
      _RentalReturnStatusScreenState();
}

class _RentalReturnStatusScreenState extends State<RentalReturnStatusScreen>
    with WidgetsBindingObserver {
  late RentalModel _rental;
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _clock;
  bool _refreshing = false;
  bool _refreshAgain = false;
  String _error = '';
  MobileApiService get _api => widget.api ?? MobileApiService.instance;

  bool get _isReturnStatusTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _rental = widget.rental;
    WidgetsBinding.instance.addObserver(this);
    _events = _api.watchRentalEvents().listen((event) {
      final type = (event['event'] ?? '').toString();
      final id = event['rentalId']?.toString() ?? '';
      if (type == 'ready' ||
          type == 'verification.changed' ||
          type == 'data.changed' ||
          (type == 'rental.changed' &&
              (id.isEmpty || id == _rental.rentalId))) {
        unawaited(_refresh(silent: true));
      }
    });
    _syncClock();
    unawaited(_refresh());
  }

  void _syncClock() {
    _clock?.cancel();
    _clock = null;
    if (_isReturnStatusTest) {
      if (!_rental.isActive) return;
      _clock = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
      return;
    }
    const doneStatuses = ['COMPLETED', 'CANCELLED', 'REJECTED', 'EXPIRED'];
    if (doneStatuses.contains(_rental.normalizedStatus)) return;
    _clock = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) unawaited(_refresh(silent: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncClock();
      unawaited(_refresh(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final data = await _api.rentalRecord(_rental.rentalId);
      if (mounted) {
        setState(() {
          _rental = RentalModel.fromMap(data, id: _rental.rentalId);
          _error = '';
        });
        _syncClock();
      }
    } catch (error) {
      if (mounted && !silent) setState(() => _error = '$error');
    } finally {
      _refreshing = false;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        unawaited(_refresh(silent: silent));
      }
    }
  }

  int _step() {
    if (_rental.normalizedStatus == 'COMPLETED') return 3;
    if (_rental.isReturnAwaitingTerminalConfirmation) return 2;
    if (_rental.isAwaitingInspection) return 1;
    return 0;
  }

  String _title() {
    if (_rental.normalizedStatus == 'COMPLETED') return 'Return confirmed';
    if (_rental.isReturnAwaitingTerminalConfirmation) {
      return 'Receipt check · counter terminal';
    }
    if (_rental.isAwaitingInspection) return 'Inspection in progress';
    if (_rental.latestReturnRequestStatus.toUpperCase() == 'REJECTED') {
      return 'Return request needs an update';
    }
    return 'Return request sent';
  }

  String _message() {
    if (_rental.normalizedStatus == 'COMPLETED') {
      return 'The inspection and receipt check are complete. This return is confirmed.';
    }
    if (_rental.isReturnAwaitingTerminalConfirmation) {
      return 'Inspection is recorded. Review, print, or save your receipt below, then confirm receipt on the ESP32 counter terminal to complete your return.';
    }
    if (_rental.isAwaitingInspection) {
      return 'The admin recorded physical receipt at ${_date(_rental.receivedAt)}. The rental timer stopped while the item and accessories are inspected.';
    }
    if (_rental.latestReturnRequestStatus.toUpperCase() == 'REJECTED') {
      return 'The admin did not accept this return request. Read the note in Notifications or contact the admin, then submit a new request when ready.';
    }
    return 'Bring the equipment to the admin. No phone QR code is needed — staff will scan the equipment label, inspect it, and confirm receipt.';
  }

  String _date(DateTime? value) => value == null
      ? 'Not recorded'
      : DateFormat('MMM d · h:mm a').format(value.toLocal());

  Future<void> _requestAgain() async {
    await Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ReturnEquipmentScreen(rental: _rental, api: widget.api)));
  }

  void _done() {
    if (widget.onDone != null) {
      widget.onDone!();
      return;
    }
    CustomerHomeScreen.returnToHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final rejected =
        _rental.latestReturnRequestStatus.toUpperCase() == 'REJECTED';
    final returned = _rental.normalizedStatus == 'COMPLETED';
    final showReceipt =
        returned || _rental.isReturnAwaitingTerminalConfirmation;
    final overdue = _rental.isActive &&
        _rental.dueDate.millisecondsSinceEpoch > 0 &&
        ServerClock.instance.now.isAfter(_rental.dueDate);
    return LiquidGlassScope(
        child: Scaffold(
            appBar: GlassAppBar(titleText: 'Return status', actions: [
              HeaderActionPod(
                  tooltip: 'Refresh return status',
                  onTap: _refresh,
                  icon: Icons.refresh_rounded)
            ]),
            bottomNavigationBar: returned
                ? RentalActionBar(
                    key: const ValueKey('return-done-button'),
                    label: 'Done',
                    onPressed: _done,
                  )
                : rejected && _rental.isActive
                    ? SafeArea(
                        minimum: const EdgeInsets.all(16),
                        child: FilledButton.icon(
                            onPressed: _requestAgain,
                            icon: const Icon(Icons.assignment_return_outlined),
                            label: const Text('Send a new return request')))
                    : null,
            backgroundColor: Colors.transparent,
            body: LiquidAmbientBackdrop(
              child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        RentalSection(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              Text(_rental.itemName,
                                  style: const TextStyle(
                                      fontSize: 25,
                                      letterSpacing: -.6,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(_rental.displayReference),
                              const SizedBox(height: 16),
                              RentalStatusBadge(
                                  status: _rental
                                          .isReturnAwaitingTerminalConfirmation
                                      ? 'PENDING_RETURN_VERIFICATION'
                                      : _rental.hasPendingReturnRequest
                                          ? 'RETURN_REQUESTED'
                                          : _rental.normalizedStatus),
                              const SizedBox(height: 20),
                              _ReturnProgressTracker(step: _step()),
                              const SizedBox(height: 18),
                              RentalNotice(
                                  title: _title(),
                                  message: _message(),
                                  icon: Icons.assignment_return_outlined,
                                  isError: rejected),
                              if (overdue) ...[
                                const SizedBox(height: 12),
                                RentalNotice(
                                    title: 'Overdue',
                                    isError: true,
                                    message:
                                        'The rental clock is still running until the admin records physical receipt.'),
                              ],
                              if (_error.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                RentalNotice(
                                    title: 'Showing your last saved status',
                                    isError: true,
                                    message:
                                        'Check your internet connection, then tap refresh to try again.'),
                              ],
                              const SizedBox(height: 12),
                              RentalValueRow(
                                  'Return by',
                                  _rental.dueDate.millisecondsSinceEpoch > 0
                                      ? _date(_rental.dueDate)
                                      : 'Not recorded'),
                              if (_rental.receivedAt != null)
                                RentalValueRow('Received by admin',
                                    _date(_rental.receivedAt)),
                              if (_rental.balanceDue > 0)
                                RentalValueRow('Balance due',
                                    rentalMoney(_rental.balanceDue)),
                            ])),
                        if (showReceipt)
                          RentalReceiptCard(
                            key: const ValueKey('return-status-receipt-card'),
                            rental: _rental,
                            isPreview: !returned,
                            onPrintOrSavePdf: widget.onPrintOrSavePdf,
                            onSharePdf: widget.onSharePdf,
                          ),
                      ])),
            )));
  }
}

class _ReturnProgressTracker extends StatelessWidget {
  const _ReturnProgressTracker({required this.step});

  final int step;

  static const labels = [
    'Request sent',
    'Inspection',
    'Receipt check',
    'Returned'
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = theme.colorScheme.primary;
    final track = theme.colorScheme.outline.withValues(alpha: .45);
    return Semantics(
        label: 'Return progress: ${labels[step]} stage',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              height: 18,
              child: CustomPaint(
                  painter: _ReturnProgressPainter(
                      step: step,
                      active: active,
                      track: track,
                      surface: theme.colorScheme.surface))),
          const SizedBox(height: 6),
          Row(children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                  child: Text(labels[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: index <= step
                              ? active
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)))
          ])
        ]));
  }
}

class _ReturnProgressPainter extends CustomPainter {
  const _ReturnProgressPainter(
      {required this.step,
      required this.active,
      required this.track,
      required this.surface});
  final int step;
  final Color active, track, surface;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 5.5;
    final startX = radius;
    final endX = size.width - radius;
    final spacing =
        (endX - startX) / (_ReturnProgressTracker.labels.length - 1);
    final centerY = size.height / 2;
    canvas.drawLine(
        Offset(startX, centerY),
        Offset(endX, centerY),
        Paint()
          ..color = track
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        Offset(startX, centerY),
        Offset(startX + spacing * step, centerY),
        Paint()
          ..color = active
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    for (var index = 0; index < _ReturnProgressTracker.labels.length; index++) {
      final center = Offset(startX + spacing * index, centerY);
      if (index == step) {
        canvas.drawCircle(
            center, 8, Paint()..color = active.withValues(alpha: .16));
        canvas.drawCircle(center, radius, Paint()..color = active);
      } else {
        canvas.drawCircle(
            center, radius, Paint()..color = index < step ? active : surface);
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
  bool shouldRepaint(covariant _ReturnProgressPainter oldDelegate) =>
      oldDelegate.step != step ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.surface != surface;
}
