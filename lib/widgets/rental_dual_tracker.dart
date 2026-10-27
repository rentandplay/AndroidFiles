import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/rental_model.dart';
import '../theme/app_theme.dart';

/// Milestone event data used in the vertical activity timeline
class RentalTimelineMilestone {
  const RentalTimelineMilestone({
    required this.title,
    required this.description,
    this.timestamp,
    this.isActive = false,
    this.icon,
  });

  final String title;
  final String description;
  final DateTime? timestamp;
  final bool isActive;
  final IconData? icon;
}

/// Dual Progress Tracker combining:
/// 1. Horizontal Macro Stepper (Request -> Handoff -> In use -> Return)
/// 2. Vertical Granular Activity Timeline (Live chronological events with timestamps)
class RentalDualTracker extends StatefulWidget {
  const RentalDualTracker({
    super.key,
    required this.rental,
    required this.step,
  });

  final RentalModel rental;
  final int step;

  @override
  State<RentalDualTracker> createState() => _RentalDualTrackerState();
}

class _RentalDualTrackerState extends State<RentalDualTracker> {
  bool _expanded = false;

  String _formatTime(DateTime? date) {
    if (date == null || date.millisecondsSinceEpoch == 0) return '—';
    final local = date.toUtc().add(const Duration(hours: 8));
    return DateFormat('h:mm a').format(local);
  }

  String _formatDate(DateTime? date) {
    if (date == null || date.millisecondsSinceEpoch == 0) return '';
    final local = date.toUtc().add(const Duration(hours: 8));
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Today';
    }
    return DateFormat('MMM d').format(local);
  }

  List<RentalTimelineMilestone> _buildMilestones() {
    final rental = widget.rental;
    final milestones = <RentalTimelineMilestone>[];

    final isReturnStage = rental.isAwaitingInspection ||
        (rental.isPendingVerification &&
            rental.normalizedStatus.contains('RETURN')) ||
        rental.normalizedStatus == 'COMPLETED';

    // 1. Completion / Inspection Finished
    if (rental.normalizedStatus == 'COMPLETED') {
      milestones.add(RentalTimelineMilestone(
        title: 'Rental Completed & Cleared',
        description: rental.conditionNotes.isNotEmpty
            ? 'Condition: ${rental.returnCondition} · ${rental.conditionNotes}'
            : 'Returned in ${rental.returnCondition} condition. Deposit settled.',
        timestamp: rental.returnedDate ?? rental.receivedAt,
        isActive: true,
        icon: Icons.check_circle_rounded,
      ));
    }

    // 2. Physical Return Received at Hub / Inspection in progress
    if (rental.receivedAt != null || rental.isAwaitingInspection) {
      final isTop = milestones.isEmpty;
      milestones.add(RentalTimelineMilestone(
        title: 'Received at Hub · Inspection Pending',
        description:
            'Staff recorded physical receipt. Rental timer stopped. Testing hardware and items.',
        timestamp: rental.receivedAt ?? rental.returnedDate,
        isActive: isTop,
        icon: Icons.fact_check_outlined,
      ));
    }

    // 3. Return Request Sent by customer
    if (rental.hasPendingReturnRequest) {
      final isTop = milestones.isEmpty;
      milestones.add(RentalTimelineMilestone(
        title: 'Return Request Sent',
        description:
            'Return request received. Hand the equipment to staff to stop rental timer.',
        timestamp: DateTime.now(),
        isActive: isTop,
        icon: Icons.assignment_return_outlined,
      ));
    }

    // 4. In Use / Active Rental
    if (rental.isActive || isReturnStage) {
      final isTop = milestones.isEmpty;
      final dueText = rental.dueDate.millisecondsSinceEpoch > 0
          ? 'Due at ${_formatTime(rental.dueDate)} (${_formatDate(rental.dueDate)})'
          : 'Return deadline active';
      milestones.add(RentalTimelineMilestone(
        title: 'Active Rental · In Use',
        description: 'Handoff confirmed. Rental timer running. $dueText.',
        timestamp: rental.startDate.millisecondsSinceEpoch > 0
            ? rental.startDate
            : null,
        isActive: isTop,
        icon: Icons.play_arrow_rounded,
      ));
    }

    // 5. Preparation & Delivery / Dispatch (Handoff stage)
    if (rental.isAwaitingPickup || rental.isActive || isReturnStage) {
      final isPrepared = rental.deliveryStatus.toUpperCase() == 'PREPARED';
      final isOutForDelivery =
          rental.deliveryStatus.toUpperCase() == 'OUT_FOR_DELIVERY';

      if (isOutForDelivery) {
        final isTop = milestones.isEmpty;
        milestones.add(RentalTimelineMilestone(
          title: 'Out for Delivery · Lakewoods',
          description:
              'Driver is en route to ${rental.deliveryLocation}. Please have your valid ID & QR code ready.',
          timestamp: null,
          isActive: isTop,
          icon: Icons.local_shipping_outlined,
        ));
      } else if (isPrepared) {
        final isTop = milestones.isEmpty;
        milestones.add(RentalTimelineMilestone(
          title: rental.isRentAndPlayPickup
              ? 'Ready for Shop Handover'
              : 'Equipment Prepared for Delivery',
          description: rental.isRentAndPlayPickup
              ? 'Item sanitized and inspected at Rent & Play Hub. Show your QR code at counter.'
              : 'Equipment packed and ready for delivery to ${rental.deliveryLocation}.',
          timestamp: null,
          isActive: isTop,
          icon: Icons.inventory_2_outlined,
        ));
      } else if (rental.isAwaitingPickup) {
        final isTop = milestones.isEmpty;
        milestones.add(RentalTimelineMilestone(
          title: 'Approved · Preparing Equipment',
          description:
              'Staff is inspecting and preparing your reserved equipment at the hub.',
          timestamp: null,
          isActive: isTop,
          icon: Icons.hourglass_top_rounded,
        ));
      }
    }

    // 6. Payment Review (If GCash / QR Proof)
    final isQr = rental.paymentMethod.toUpperCase() == 'QR';
    if (isQr && rental.paymentProofStatus == 'REJECTED') {
      final isTop = milestones.isEmpty;
      milestones.add(RentalTimelineMilestone(
        title: 'Payment Screenshot Needs Update',
        description: rental.paymentProofNote.isNotEmpty
            ? rental.paymentProofNote
            : 'Screenshot could not be verified. Please upload a clear receipt.',
        timestamp: null,
        isActive: isTop,
        icon: Icons.error_outline_rounded,
      ));
    } else if (isQr && rental.paymentProofStatus == 'PENDING_REVIEW') {
      final isTop = milestones.isEmpty;
      milestones.add(RentalTimelineMilestone(
        title: 'Payment Screenshot Under Review',
        description:
            'Staff is checking your GCash payment proof. Hold is active.',
        timestamp: null,
        isActive: isTop,
        icon: Icons.receipt_long_outlined,
      ));
    }

    // 7. Initial Booking Request
    final isTop = milestones.isEmpty;
    final initialDescription = rental.isPendingAdminReview
        ? 'Request placed. Waiting for staff review.'
        : 'Rental request created for ${rental.itemName}.';
    milestones.add(RentalTimelineMilestone(
      title: 'Rental Request Placed',
      description: initialDescription,
      timestamp: rental.startDate.millisecondsSinceEpoch > 0
          ? rental.startDate
          : null,
      isActive: isTop,
      icon: Icons.app_registration_rounded,
    ));

    return milestones;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final milestones = _buildMilestones();
    final topMilestone = milestones.isNotEmpty
        ? milestones.first
        : const RentalTimelineMilestone(
            title: 'In Progress', description: 'Status updated');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Horizontal Macro Stepper (Request -> Handoff -> In use -> Return)
        RentalMacroStepper(step: widget.step),
        const SizedBox(height: 10),

        // 2. Vertical Activity Timeline (Collapsible Live Log)
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          // First Child: Compact Live Ticker (1-line)
          firstChild: InkWell(
            onTap: () => setState(() => _expanded = true),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: scheme.outline.withValues(alpha: .18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppTheme.brandOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${topMilestone.title}: ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brandOrange,
                            ),
                          ),
                          TextSpan(
                            text: topMilestone.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: AppTheme.brandOrange),
                ],
              ),
            ),
          ),
          // Second Child: Expanded Vertical Detailed Log
          secondChild: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: scheme.outline.withValues(alpha: .2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header line of the Activity Log
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 14, color: AppTheme.brandOrange),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'LIVE ACTIVITY LOG',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.brandOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Live',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brandOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Chronological Vertical Timeline entries
                for (var i = 0; i < milestones.length; i++)
                  _VerticalMilestoneRow(
                    milestone: milestones[i],
                    isFirst: i == 0,
                    isLast: i == milestones.length - 1,
                    formatTime: _formatTime,
                    formatDate: _formatDate,
                  ),

                // Collapse Action
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => setState(() => _expanded = false),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Show less',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.brandOrange,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 16,
                          color: AppTheme.brandOrange,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Single row item in the vertical activity timeline
class _VerticalMilestoneRow extends StatelessWidget {
  const _VerticalMilestoneRow({
    required this.milestone,
    required this.isFirst,
    required this.isLast,
    required this.formatTime,
    required this.formatDate,
  });

  final RentalTimelineMilestone milestone;
  final bool isFirst;
  final bool isLast;
  final String Function(DateTime?) formatTime;
  final String Function(DateTime?) formatDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = AppTheme.brandOrange;
    final isActive = milestone.isActive;

    final dateStr = formatDate(milestone.timestamp);
    final timeStr = formatTime(milestone.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Timestamp (Date & Time) - constrained for small screens
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, maxWidth: 54),
            child: Padding(
              padding: const EdgeInsets.only(top: 1, right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      color: isActive ? activeColor : scheme.onSurface,
                    ),
                  ),
                  if (dateStr.isNotEmpty)
                    Text(
                      dateStr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Center: Spine (Dot + Vertical line)
          Column(
            children: [
              // Node Dot
              if (isActive)
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(alpha: .35),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 4.5,
                      height: 4.5,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(vertical: 2.5),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: .65),
                      width: 1.8,
                    ),
                  ),
                ),

              // Vertical connecting line
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 2.5),
                    color: scheme.outline.withValues(alpha: .35),
                  ),
                ),
            ],
          ),

          // Right: Content Title & Description
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: 8,
                bottom: isLast ? 4 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    milestone.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                      color: isActive ? activeColor : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Text(
                    milestone.description,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: isActive
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal Macro Stepper displaying the 4 core stages of rental:
/// Request -> Handoff -> In use -> Return
class RentalMacroStepper extends StatelessWidget {
  const RentalMacroStepper({super.key, required this.step});

  final int step;
  static const _labels = ['Request', 'Handoff', 'In use'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = AppTheme.brandOrange;
    final track = scheme.outline.withValues(alpha: .4);
    final labels = step == 3 ? [..._labels, 'Return'] : _labels;

    return Semantics(
      label: 'Rental progress: ${labels[step.clamp(0, labels.length - 1)]} stage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 18,
            child: CustomPaint(
              painter: _RentalMacroPainter(
                step: step.clamp(0, labels.length - 1),
                stepCount: labels.length,
                active: active,
                track: track,
                surface: scheme.surface,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: index <= step ? active : scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight:
                          index == step ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RentalMacroPainter extends CustomPainter {
  const _RentalMacroPainter({
    required this.step,
    required this.stepCount,
    required this.active,
    required this.track,
    required this.surface,
  });

  final int step, stepCount;
  final Color active, track, surface;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 5.5;
    final centerY = size.height / 2;
    final startX = radius;
    final endX = size.width - radius;
    final spacing = (endX - startX) / (stepCount - 1);

    // Track line
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
      canvas.drawLine(
        Offset(startX, centerY),
        Offset(startX + spacing * step, centerY),
        activePaint,
      );
    }

    // Circles
    for (var index = 0; index < stepCount; index++) {
      final center = Offset(startX + spacing * index, centerY);
      if (index == step) {
        // Active glowing node
        canvas.drawCircle(
          center,
          8,
          Paint()
            ..color = active.withValues(alpha: .18)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = active
            ..style = PaintingStyle.fill,
        );
      } else {
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = index < step ? active : surface
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = index < step ? active : track
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RentalMacroPainter oldDelegate) =>
      oldDelegate.step != step ||
      oldDelegate.stepCount != stepCount ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.surface != surface;
}
