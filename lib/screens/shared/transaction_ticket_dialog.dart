import '../../services/server_clock.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/rental_model.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_api_service.dart';
import '../../services/rental_offline_cache.dart';
import '../../widgets/rental_ui.dart';

bool get _isTicketTest =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Animated subtle holographic shimmer border around a crisp white QR mat.
class _HolographicQrRim extends StatefulWidget {
  const _HolographicQrRim({
    required this.child,
    this.padding = 10,
    this.radius = 18,
  });

  final Widget child;
  final double padding;
  final double radius;

  @override
  State<_HolographicQrRim> createState() => _HolographicQrRimState();
}

class _HolographicQrRimState extends State<_HolographicQrRim>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
      value: 0.22,
    );
    if (!_isTicketTest) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _controller.value * math.pi * 2;
        return Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: SweepGradient(
              transform: GradientRotation(angle),
              colors: const [
                Color(0xFFDF762D),
                Color(0xFFFBBF24),
                Color(0xFF38BDF8),
                Color(0xFFA78BFA),
                Color(0xFFDF762D),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDF762D).withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        padding: EdgeInsets.all(widget.padding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(widget.radius - 2.5),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Ticket perforation divider with semicircular edge cutouts and a dashed tear line.
class _PerforatedPassDivider extends StatelessWidget {
  const _PerforatedPassDivider({
    required this.notchColor,
    required this.topColor,
    required this.bottomColor,
    required this.dashColor,
  });

  final Color notchColor;
  final Color topColor;
  final Color bottomColor;
  final Color dashColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: CustomPaint(
        painter: _PerforatedPassPainter(
          notchColor: notchColor,
          topColor: topColor,
          bottomColor: bottomColor,
          dashColor: dashColor,
        ),
      ),
    );
  }
}

class _PerforatedPassPainter extends CustomPainter {
  const _PerforatedPassPainter({
    required this.notchColor,
    required this.topColor,
    required this.bottomColor,
    required this.dashColor,
  });

  final Color notchColor;
  final Color topColor;
  final Color bottomColor;
  final Color dashColor;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, midY),
      Paint()..color = topColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, midY, size.width, size.height - midY),
      Paint()..color = bottomColor,
    );

    const notchRadius = 9.0;
    final dashPaint = Paint()
      ..color = dashColor
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    var x = notchRadius + 7;
    final maxX = size.width - notchRadius - 7;
    while (x < maxX) {
      final endX = math.min(x + 5.0, maxX);
      canvas.drawLine(Offset(x, midY), Offset(endX, midY), dashPaint);
      x += 9.5;
    }

    final notchPaint = Paint()..color = notchColor;
    canvas.drawCircle(Offset(0, midY), notchRadius, notchPaint);
    canvas.drawCircle(Offset(size.width, midY), notchRadius, notchPaint);
  }

  @override
  bool shouldRepaint(covariant _PerforatedPassPainter oldDelegate) {
    return oldDelegate.notchColor != notchColor ||
        oldDelegate.topColor != topColor ||
        oldDelegate.bottomColor != bottomColor ||
        oldDelegate.dashColor != dashColor;
  }
}

/// Compact circular countdown pill rendered inside the pass header.
class _HoldCountdownBadge extends StatefulWidget {
  const _HoldCountdownBadge({
    required this.expiry,
    required this.expired,
  });

  final DateTime expiry;
  final bool expired;

  @override
  State<_HoldCountdownBadge> createState() => _HoldCountdownBadgeState();
}

class _HoldCountdownBadgeState extends State<_HoldCountdownBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!_isTicketTest && !widget.expired) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ServerClock.instance.now;
    final remaining = widget.expiry.difference(now);
    final isExpired = widget.expired || remaining <= Duration.zero;

    // Normalize ring fraction against a 2-hour pickup/review window when short,
    // or 24-hour hold window so the arc visibly communicates urgency.
    final windowMinutes = remaining.inMinutes > 120 ? 1440 : 120;
    final progress = isExpired
        ? 0.0
        : (remaining.inSeconds / (windowMinutes * 60)).clamp(0.06, 1.0);
    final ringColor = isExpired
        ? const Color(0xFFEF4444)
        : remaining.inMinutes <= 20
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);

    String label;
    if (isExpired) {
      label = 'Expired';
    } else if (remaining.inHours >= 24) {
      final days = remaining.inDays;
      final hours = remaining.inHours % 24;
      label = '${days}d ${hours}h left';
    } else if (remaining.inHours >= 1) {
      final h = remaining.inHours.toString().padLeft(2, '0');
      final m = (remaining.inMinutes % 60).toString().padLeft(2, '0');
      final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      label = '$h:$m:$s';
    } else {
      final m = remaining.inMinutes.toString().padLeft(2, '0');
      final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      label = '$m:$s left';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ringColor.withValues(alpha: 0.48)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CustomPaint(
              painter: _HoldCountdownRingPainter(
                progress: progress,
                color: ringColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isExpired ? const Color(0xFFFCA5A5) : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldCountdownRingPainter extends CustomPainter {
  const _HoldCountdownRingPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - 2.6) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HoldCountdownRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

String _resolveTicketCacheScope(BuildContext context, RentalModel rental) {
  try {
    final uid = Provider.of<AuthService>(context, listen: false).currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) return uid.trim();
  } catch (_) {
    // AuthService provider may be absent in isolated widget tests.
  }
  return rental.customerId.trim();
}

Future<Map<String, dynamic>> _loadRentalTicketWithOfflineCache({
  required MobileApiService api,
  required RentalModel rental,
  required String scope,
  VoidCallback? onHandedOff,
}) async {
  try {
    final live = await api.rentalTicket(rental.rentalId);
    await RentalOfflineCache.saveTicket(scope, rental.rentalId, live);
    return live;
  } catch (error) {
    final errText = error.toString().toLowerCase();
    final isAlreadyInUse = (error is MobileApiException && error.statusCode == 409) &&
        (errText.contains('already in use') || errText.contains('no longer available'));
    if (isAlreadyInUse && onHandedOff != null) {
      Future.microtask(onHandedOff);
    }
    final alreadyHandedOff = isAlreadyInUse ||
        rental.isActive ||
        rental.isAwaitingInspection ||
        rental.hasPendingReturnRequest;
    if (!alreadyHandedOff) {
      final cached = await RentalOfflineCache.loadTicket(scope, rental.rentalId);
      if (cached != null) return cached;
    }
    rethrow;
  }
}

class TransactionTicketDialog {
  static Future<void> show(BuildContext context, RentalModel rental) =>
      showDialog<void>(
        context: context,
        builder: (_) => BookingTicket(rental: rental),
      );
}

class BookingTicket extends StatefulWidget {
  const BookingTicket({super.key, required this.rental, this.api});
  final RentalModel rental;
  final MobileApiService? api;
  @override
  State<BookingTicket> createState() => _BookingTicketState();
}

class _BookingTicketState extends State<BookingTicket> {
  late Future<Map<String, dynamic>> _ticket;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  void _load() {
    final scope = _resolveTicketCacheScope(context, widget.rental);
    _ticket = _loadRentalTicketWithOfflineCache(
      api: widget.api ?? MobileApiService.instance,
      rental: widget.rental,
      scope: scope,
    );
  }

  void _retry() => setState(_load);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = theme.dialogTheme.backgroundColor ??
        scheme.surfaceContainerHigh;
    final passBodyBg =
        isDark ? const Color(0xFF161E2B) : const Color(0xFFFFFCFA);
    const passNavyTop = Color(0xFF091321);
    const passNavyBottom = Color(0xFF142642);

    return AlertDialog(
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.all(16),
      contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      constraints: BoxConstraints(
          maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * .86),
      title: const Text('Your rental handoff QR'),
      content: SizedBox(
        width: 340,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _ticket,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final alreadyHandedOff = widget.rental.isActive ||
                  widget.rental.isAwaitingInspection ||
                  widget.rental.hasPendingReturnRequest;
              return RentalNotice(
                  isError: true,
                  title: alreadyHandedOff
                      ? 'Handoff QR no longer available'
                      : 'Ticket unavailable',
                  message: alreadyHandedOff
                      ? 'This rental has already been handed off. Use the return status on My Rentals; the admin records the return with the rental code.'
                      : '${snapshot.error}',
                  action: TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again')));
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()));
            }
            final data = snapshot.data!;
            final isOfflineCached = data['offline_cached'] == true;
            final status = data['status']?.toString() ??
                widget.rental.normalizedStatus;
            final expiry = DateTime.tryParse(
                data['hold_expires_at']?.toString() ?? '');
            final expired = status == 'APPROVED' &&
                expiry != null &&
                ServerClock.instance.now.isAfter(expiry);
            final image = data['image_data_url']?.toString() ?? '';
            final code =
                data['rental_code']?.toString() ?? widget.rental.rentalCode;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOfflineCached) ...[
                    RentalNotice(
                      icon: Icons.wifi_off_rounded,
                      title: 'Offline saved QR pass',
                      message:
                          'Showing your last saved handoff QR while offline. Staff can still scan this QR or verify your rental code.',
                      action: TextButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Try again'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : const Color(0xFFE7DDD3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.34 : 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [passNavyTop, passNavyBottom],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDF762D)
                                            .withValues(alpha: 0.18),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                          color: const Color(0xFFDF762D)
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isOfflineCached
                                                ? Icons.wifi_off_rounded
                                                : Icons
                                                    .confirmation_number_rounded,
                                            size: 12,
                                            color: const Color(0xFFFBBF24),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            isOfflineCached
                                                ? 'OFFLINE PASS'
                                                : 'RENT & PLAY PASS',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.7,
                                              color: Color(0xFFFDE68A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (expiry != null)
                                      _HoldCountdownBadge(
                                        expiry: expiry,
                                        expired: expired,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.rental.itemName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    RentalStatusBadge(status: status),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          widget.rental.isRentAndPlayPickup
                                              ? Icons.storefront_rounded
                                              : Icons.local_shipping_rounded,
                                          size: 13,
                                          color: Colors.white70,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            widget.rental.isRentAndPlayPickup
                                                ? 'Shop pickup'
                                                : 'Courier handoff',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _PerforatedPassDivider(
                            notchColor: dialogBg,
                            topColor: passNavyBottom,
                            bottomColor: passBodyBg,
                            dashColor: isDark
                                ? Colors.white.withValues(alpha: 0.16)
                                : const Color(0xFFD6C9BD),
                          ),
                          Container(
                            color: passBodyBg,
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (status == 'APPROVED' &&
                                    !expired &&
                                    image.startsWith('data:image/png;base64,')) ...[
                                  GestureDetector(
                                    key: const ValueKey('booking-ticket-qr-tap'),
                                    onTap: () => FullscreenQrScanDialog.show(
                                      context,
                                      imageDataUrl: image,
                                      rentalCode: code,
                                      itemName: widget.rental.itemName,
                                      rollingPin:
                                          data['rolling_pin']?.toString() ?? '',
                                    ),
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 230),
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: _HolographicQrRim(
                                          padding: 10,
                                          radius: 18,
                                          child: Image.memory(
                                            base64Decode(image.split(',').last),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fullscreen_rounded,
                                          size: 14, color: scheme.primary),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Tap QR for bright scan mode',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : const Color(0xFFF6F1EB),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : const Color(0xFFE7DDD3),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'RENTAL PASS CODE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        code,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.4,
                                          color: scheme.onSurface,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures()
                                          ],
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          await Clipboard.setData(
                                              ClipboardData(text: code));
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'Rental code copied.')));
                                          }
                                        },
                                        icon: const Icon(Icons.copy, size: 15),
                                        label: const Text('Copy rental code'),
                                      ),
                                    ],
                                  ),
                                ),
                                if (expiry != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    '${status == 'PENDING_ADMIN_APPROVAL' ? 'Review hold ends' : 'Handoff before'} ${DateFormat('MMM d · h:mm a').format(expiry.toLocal())}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                RentalNotice(
                                  title: expired
                                      ? 'This hold has ended'
                                      : status == 'PENDING_ADMIN_APPROVAL'
                                          ? 'Request under review'
                                          : widget.rental.isRentAndPlayPickup
                                              ? 'Show this to Rent & Play'
                                              : 'Show this to delivery staff',
                                  isError: expired,
                                  message: expired
                                      ? 'Close this ticket and refresh My Rentals to check your rental request.'
                                      : status == 'PENDING_ADMIN_APPROVAL'
                                          ? 'Your request is still under review. Rental time starts only when staff hands the item over to you at ${widget.rental.customerHandoffLocation}.'
                                          : widget.rental.isRentAndPlayPickup
                                              ? 'Show your rental QR code and a valid ID to staff at ${widget.rental.customerHandoffLocation} for shop handover.'
                                              : 'Bring a valid ID. Delivery staff will scan the QR code when they hand over your item at ${widget.rental.customerHandoffLocation}.',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'))
      ],
    );
  }
}

class EmbeddedRentalHandoffQr extends StatefulWidget {
  const EmbeddedRentalHandoffQr({
    super.key,
    required this.rental,
    this.api,
    this.onHandedOff,
  });

  final RentalModel rental;
  final MobileApiService? api;
  final VoidCallback? onHandedOff;

  @override
  State<EmbeddedRentalHandoffQr> createState() =>
      _EmbeddedRentalHandoffQrState();
}

class _EmbeddedRentalHandoffQrState extends State<EmbeddedRentalHandoffQr> {
  late Future<Map<String, dynamic>> _ticketFuture;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant EmbeddedRentalHandoffQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rental.rentalId != widget.rental.rentalId ||
        oldWidget.rental.deliveryStatus != widget.rental.deliveryStatus) {
      _load();
    }
  }

  void _load() {
    final scope = _resolveTicketCacheScope(context, widget.rental);
    _ticketFuture = _loadRentalTicketWithOfflineCache(
      api: widget.api ?? MobileApiService.instance,
      rental: widget.rental,
      scope: scope,
      onHandedOff: widget.onHandedOff,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _ticketFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.error.withValues(alpha: .3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: scheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'QR code ticket unavailable: ${snapshot.error}',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ),
                TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return Container(
            height: 110,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.primary)),
                const SizedBox(height: 8),
                Text('Loading live handoff QR & rolling PIN...',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        final isOfflineCached = data['offline_cached'] == true;
        final status =
            data['status']?.toString() ?? widget.rental.normalizedStatus;
        final expiry =
            DateTime.tryParse(data['hold_expires_at']?.toString() ?? '');
        final expired = status == 'APPROVED' &&
            expiry != null &&
            ServerClock.instance.now.isAfter(expiry);
        final image = data['image_data_url']?.toString() ?? '';
        final code =
            data['rental_code']?.toString() ?? widget.rental.rentalCode;
        final rollingPin = data['rolling_pin']?.toString() ?? '';

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final notchBg = Theme.of(context).colorScheme.surface;
        final passBodyBg =
            isDark ? const Color(0xFF1A2332) : const Color(0xFFFFFCFA);
        const passNavyTop = Color(0xFF091321);
        const passNavyBottom = Color(0xFF152742);

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFFE7DDD3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [passNavyTop, passNavyBottom],
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOfflineCached
                                ? Icons.wifi_off_rounded
                                : Icons.qr_code_2_rounded,
                            size: 16,
                            color: const Color(0xFFDF762D),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isOfflineCached
                                  ? 'SAVED OFFLINE HANDOVER QR'
                                  : 'LIVE HANDOVER QR & PIN',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                                color: Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (expiry != null)
                        _HoldCountdownBadge(
                          expiry: expiry,
                          expired: expired,
                        ),
                    ],
                  ),
                ),
                _PerforatedPassDivider(
                  notchColor: notchBg,
                  topColor: passNavyBottom,
                  bottomColor: passBodyBg,
                  dashColor: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : const Color(0xFFD6C9BD),
                ),
                Container(
                  color: passBodyBg,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!expired &&
                          image.startsWith('data:image/png;base64,')) ...[
                        GestureDetector(
                          key: const ValueKey('embedded-handoff-qr-tap'),
                          onTap: () => FullscreenQrScanDialog.show(
                            context,
                            imageDataUrl: image,
                            rentalCode: code,
                            itemName: widget.rental.itemName,
                            rollingPin: rollingPin,
                          ),
                          child: _HolographicQrRim(
                            padding: 9,
                            radius: 16,
                            child: SizedBox(
                              width: 168,
                              height: 168,
                              child: Image.memory(
                                base64Decode(image.split(',').last),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => FullscreenQrScanDialog.show(
                            context,
                            imageDataUrl: image,
                            rentalCode: code,
                            itemName: widget.rental.itemName,
                            rollingPin: rollingPin,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen_rounded,
                                    size: 15, color: scheme.primary),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Tap QR for high-contrast scan mode',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (rollingPin.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFF6F1EB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: .30),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '6-DIGIT ROLLING PIN',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                rollingPin,
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3.5,
                                  color: scheme.onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SelectableText(
                        'Rental code: $code',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isOfflineCached
                            ? 'Saved offline copy · Rolling PIN requires signal, but staff can scan this QR or verify your rental code.'
                            : widget.rental.isRentAndPlayPickup
                                ? 'Show this QR or 6-digit PIN at the counter to start your rental timer.'
                                : 'Show this QR or 6-digit PIN to the delivery rider at ${widget.rental.deliveryLocation}. Timer starts upon scan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      if (isOfflineCached) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => setState(_load),
                          icon: const Icon(Icons.refresh, size: 15),
                          label: const Text('Retry live'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FullscreenQrScanDialog extends StatelessWidget {
  const FullscreenQrScanDialog({
    super.key,
    required this.imageDataUrl,
    required this.rentalCode,
    required this.itemName,
    this.rollingPin = '',
  });

  final String imageDataUrl;
  final String rentalCode;
  final String itemName;
  final String rollingPin;

  static Future<void> show(
    BuildContext context, {
    required String imageDataUrl,
    required String rentalCode,
    required String itemName,
    String rollingPin = '',
  }) {
    HapticFeedback.lightImpact();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (_) => FullscreenQrScanDialog(
        imageDataUrl: imageDataUrl,
        rentalCode: rentalCode,
        itemName: itemName,
        rollingPin: rollingPin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navyTop = Color(0xFF091321);
    const navyBottom = Color(0xFF152742);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [navyTop, navyBottom],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDF762D)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFDF762D)
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.wb_sunny_rounded,
                                        size: 14, color: Color(0xFFFBBF24)),
                                    SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'HIGH-CONTRAST SCAN MODE',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.6,
                                          color: Color(0xFFFDE68A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close fullscreen QR',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        itemName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const _PerforatedPassDivider(
                  notchColor: Color(0xFF0B1220),
                  topColor: navyBottom,
                  bottomColor: Colors.white,
                  dashColor: Color(0xFFCBD5E1),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HolographicQrRim(
                        padding: 14,
                        radius: 20,
                        child: SizedBox(
                          width: 240,
                          height: 240,
                          child: Image.memory(
                            base64Decode(imageDataUrl.split(',').last),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (rollingPin.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                '6-DIGIT ROLLING PIN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: Color(0xFFDF762D),
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                rollingPin,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  color: Color(0xFF0F172A),
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SelectableText(
                        rentalCode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFF334155),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Present this high-contrast pass to the Rent & Play operator or delivery rider.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
