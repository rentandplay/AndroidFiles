import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/rental_notification.dart';
import '../../services/notification_service.dart';
import '../../widgets/rental_ui.dart';
import 'alerts_screen.dart';
import 'notification_booking_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.initialId});
  final String? initialId;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _openedInitial = false, _marking = false;
  Future<void> _open(
      RentalNotification row, RentalNotificationService service) async {
    try {
      await service.markRead([row.id]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NotificationBookingScreen(
                notification: row,
                audience: service.audience,
                api: service.api)));
    if (mounted) await service.refresh();
  }

  Future<void> _markRead(RentalNotificationService service) async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      await service.markRead(service.items.map((row) => row.id));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<RentalNotificationService?>();
    if (!_openedInitial && widget.initialId != null && service != null) {
      final matches = service.items.where((row) => row.id == widget.initialId);
      if (matches.isNotEmpty) {
        _openedInitial = true;
        final row = matches.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _open(row, service);
        });
      }
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Notifications'), actions: [
          IconButton(
              tooltip: 'Mark shown as read',
              onPressed: service == null || service.unreadCount == 0 || _marking
                  ? null
                  : () => _markRead(service),
              icon: const Icon(Icons.done_all)),
          IconButton(
              tooltip: 'Refresh notifications',
              onPressed: service == null ? null : () => service.refresh(),
              icon: const Icon(Icons.refresh)),
        ]),
        body: service == null || !service.signedIn
            ? const RentalEmptyState(
                title: 'Sign in to view notifications',
                message:
                    'Booking decisions and return updates will appear here.')
            : service.loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: service.refresh,
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (service.phoneAlertsSupported)
                            Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text('Phone alerts',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          const SizedBox(height: 6),
                                          const Text(
                                              'Receive booking and return updates when the app is in the background.'),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                              onPressed: service
                                                      .enablingPhoneAlerts
                                                  ? null
                                                  : service.enablePhoneAlerts,
                                              icon: Icon(service
                                                      .phoneAlertsEnabled
                                                  ? Icons.notifications_active
                                                  : Icons
                                                      .notifications_outlined),
                                              label: Text(service
                                                      .enablingPhoneAlerts
                                                  ? 'Enabling…'
                                                  : service.phoneAlertsEnabled
                                                      ? 'Phone alerts on'
                                                      : 'Enable phone alerts')),
                                          if (service
                                              .phoneAlertError.isNotEmpty)
                                            Text(service.phoneAlertError),
                                        ]))),
                          if (service.audience == 'CUSTOMER')
                            TextButton.icon(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => const AlertsScreen())),
                                icon: const Icon(Icons.timer_outlined),
                                label: const Text('View rental timers')),
                          if (service.error.isNotEmpty) ...[
                            RentalNotice(
                                title: 'Could not refresh notifications',
                                message: service.error),
                            OutlinedButton(
                                onPressed: () => service.refresh(),
                                child: const Text('Try again'))
                          ],
                          if (service.items.isEmpty && service.error.isEmpty)
                            const RentalEmptyState(
                                title: 'No updates yet',
                                message:
                                    'You will see new requests, booking decisions and return updates here.'),
                          for (final row in service.items)
                            Card(
                                color: row.isRead
                                    ? null
                                    : Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: .22),
                                child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    leading: Icon(
                                        row.type.contains('REJECTED')
                                            ? Icons.cancel_outlined
                                            : row.type.contains('APPROVED') ||
                                                    row.type
                                                        .contains('COMPLETED')
                                                ? Icons.check_circle_outline
                                                : Icons.receipt_long_outlined,
                                        color: row.type.contains('REJECTED')
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary),
                                    title: Text(row.title,
                                        style: TextStyle(
                                            fontWeight: row.isRead
                                                ? FontWeight.w500
                                                : FontWeight.w800)),
                                    subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(row.message),
                                              const SizedBox(height: 8),
                                              Text(
                                                  '${row.rentalCode} · ${DateFormat('MMM d, h:mm a').format(row.createdAt.toUtc().add(const Duration(hours: 8)))}${row.isRead ? '' : ' · Unread'}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall)
                                            ])),
                                    onTap: () => _open(row, service))),
                          if (service.nextCursor != null)
                            OutlinedButton(
                                onPressed: () => service.refresh(older: true),
                                child: const Text('Load older updates')),
                        ])));
  }
}
