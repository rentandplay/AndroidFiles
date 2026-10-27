import 'liquid_glass.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String rentalMoney(num? value) => value == null
    ? '—'
    : NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2)
        .format(value);

String rentalStatusLabel(String status) => switch (status.toUpperCase()) {
      'PENDING_ADMIN_APPROVAL' || 'PENDING_ESP32_RENT' => 'Awaiting review',
      'APPROVED' => 'Approved · awaiting handoff',
      'ACTIVE' || 'RENTED' => 'In use',
      'RETURN_REQUESTED' => 'Return requested',
      'RETURN_PENDING_INSPECTION' => 'Inspection pending',
      'PENDING_VERIFICATION' => 'Handoff awaiting confirmation',
      'PENDING_RETURN_VERIFICATION' ||
      'PENDING_ESP32_RETURN' =>
        'Return awaiting confirmation',
      'COMPLETED' => 'Returned',
      'CANCELLED' => 'Cancelled',
      'REJECTED' => 'Declined',
      'EXPIRED' => 'Hold expired',
      _ => status.replaceAll('_', ' ').toLowerCase(),
    };

class RentalStatusBadge extends StatelessWidget {
  const RentalStatusBadge({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status.toUpperCase()) {
      'ACTIVE' ||
      'RENTED' ||
      'COMPLETED' =>
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF86EFAC)
            : const Color(0xFF166534),
      'REJECTED' || 'EXPIRED' || 'CANCELLED' => scheme.error,
      _ => Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF0AD7C)
          : const Color(0xFF9A471B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        border: Border.all(color: color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(rentalStatusLabel(status),
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class RentalSection extends StatelessWidget {
  const RentalSection(
      {super.key, this.title, this.subtitle, this.icon, required this.child});
  final String? title, subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassCard(
        margin: const EdgeInsets.only(bottom: 16),
        borderRadius: 20,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      size: 19, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                  child: Text(title!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2))),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                      fontSize: 13)),
            ],
            const SizedBox(height: 14),
          ],
          child,
        ]),
      );
}

class RentalNotice extends StatelessWidget {
  const RentalNotice(
      {super.key,
      required this.message,
      this.title,
      this.icon = Icons.info_outline,
      this.isError = false,
      this.action});
  final String? title;
  final String message;
  final IconData icon;
  final bool isError;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          border: Border.all(color: color.withValues(alpha: .2)),
          borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 21),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null) ...[
            Text(title!, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4)
          ],
          Text(message,
              style: TextStyle(
                  color: scheme.onSurface, fontSize: 13, height: 1.45)),
          if (action != null) action!,
        ])),
      ]),
    );
  }
}

class RentalValueRow extends StatelessWidget {
  const RentalValueRow(this.label, this.value,
      {super.key, this.emphasis = false});
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: emphasis
                          ? null
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13))),
          const SizedBox(width: 16),
          Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: emphasis ? 16 : 13,
                      fontWeight:
                          emphasis ? FontWeight.w800 : FontWeight.w600))),
        ]),
      );
}

class RentalActionBar extends StatelessWidget {
  const RentalActionBar(
      {super.key,
      required this.label,
      required this.onPressed,
      this.busy = false,
      this.summaryLabel,
      this.summaryValue,
      this.secondary});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String? summaryLabel, summaryValue;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final glassFill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF162030).withValues(alpha: 0.88),
              const Color(0xFF0D1420).withValues(alpha: 0.78),
            ]
          : [
              Colors.white.withValues(alpha: 0.90),
              const Color(0xFFFAF6F0).withValues(alpha: 0.80),
            ],
    );

    final specularBorder = LinearGradient(
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.22),
              const Color(0xFFDF762D).withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.10),
            ]
          : [
              Colors.white.withValues(alpha: 0.95),
              const Color(0xFFF3ECE4).withValues(alpha: 0.60),
              const Color(0xFFDF762D).withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.80),
            ],
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: glassFill,
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.35)
                      : const Color(0xFF0F172A).withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1.2,
                  child: Container(
                    decoration: BoxDecoration(gradient: specularBorder),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 712),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (summaryLabel != null) ...[
                              RentalValueRow(
                                summaryLabel!,
                                summaryValue ?? '—',
                                emphasis: true,
                              ),
                              const SizedBox(height: 8),
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF8A3D), Color(0xFFDF762D)],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFDF762D)
                                          .withValues(alpha: 0.35),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: FilledButton(
                                  onPressed: busy ? null : onPressed,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(50),
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        )
                                      : Text(
                                          label,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            if (secondary != null) secondary!,
                          ],
                        ),
                      ),
                    ),
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

class RentalSteps extends StatelessWidget {
  const RentalSteps(
      {super.key,
      required this.step,
      this.labels = const ['Rental QR', 'Handoff']});
  final int step;
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
                child: Column(children: [
              CircleAvatar(
                  radius: 16,
                  backgroundColor: i <= step
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: i < step
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text('${i + 1}',
                          style: TextStyle(
                              color: i <= step
                                  ? Colors.white
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight: FontWeight.w700))),
              const SizedBox(height: 6),
              Text(labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          i == step ? FontWeight.w700 : FontWeight.w400)),
            ])),
        ]),
      );
}

class RentalEmptyState extends StatelessWidget {
  const RentalEmptyState(
      {super.key, required this.title, required this.message, this.action});
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(children: [
        Icon(Icons.receipt_long_outlined,
            size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 6),
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]));
}
