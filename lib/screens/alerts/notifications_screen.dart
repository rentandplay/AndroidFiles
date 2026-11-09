import '../shared/support_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/rental_notification.dart';
import '../../services/notification_service.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/rental_ui.dart';
import 'alerts_screen.dart';
import 'notification_booking_screen.dart';
import '../../widgets/notification_widgets.dart';
import '../../utils/error_sanitizer.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.initialId});
  final String? initialId;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _openedInitial = false, _marking = false, _hidePhoneAlertsCard = false;
  String _filter = 'All';
  final Set<String> _dismissedIds = <String>{};

  @override
  void initState() {
    super.initState();
    RentalNotificationSuppression.isNotificationsScreenActive = true;
  }

  @override
  void dispose() {
    RentalNotificationSuppression.isNotificationsScreenActive = false;
    super.dispose();
  }

  List<RentalNotification> _filteredItems(List<RentalNotification> items) {
    return items.where((row) {
      if (_dismissedIds.contains(row.id)) return false;
      switch (_filter) {
        case 'Unread':
          return !row.isRead;
        case 'Rentals':
          return row.type != 'CHAT_MESSAGE';
        case 'Chat':
          return row.type == 'CHAT_MESSAGE';
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _open(
      RentalNotification row, RentalNotificationService service) async {
    try {
      await service.markRead([row.id]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ErrorSanitizer.format(error))));
      }
    }
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                row.type == 'CHAT_MESSAGE' && row.threadId.isNotEmpty
                    ? SupportChatScreen(
                        threadId: row.threadId,
                        staff: service.audience == 'STAFF',
                        api: service.api)
                    : NotificationBookingScreen(
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
            .showSnackBar(SnackBar(content: Text(ErrorSanitizer.format(error))));
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
    final filteredItems =
        service == null ? const <RentalNotification>[] : _filteredItems(service.items);

    return Scaffold(
        appBar: GlassAppBar(titleText: 'Notifications', actions: [
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
        body: LiquidAmbientBackdrop(
          child: service == null || !service.signedIn
              ? const RentalEmptyState(
                  title: 'Sign in to view notifications',
                  message:
                      'Rental request decisions and return updates will appear here.')
              : service.loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: service.refresh,
                      child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            if (service.phoneAlertsSupported &&
                                !_hidePhoneAlertsCard)
                              GlassCard(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text('Phone alerts',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                            ),
                                            IconButton(
                                              key: const ValueKey(
                                                  'notifications-dismiss-phone-alerts'),
                                              tooltip: 'Hide phone alerts card',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => setState(() =>
                                                  _hidePhoneAlertsCard = true),
                                              icon: const Icon(
                                                  Icons.close_rounded,
                                                  size: 18),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                            'Receive rental request and return updates when the app is in the background.'),
                                        const SizedBox(height: 12),
                                        OutlinedButton.icon(
                                            onPressed:
                                                service.enablingPhoneAlerts
                                                    ? null
                                                    : service.enablePhoneAlerts,
                                            icon: Icon(service
                                                    .phoneAlertsEnabled
                                                ? Icons.notifications_active
                                                : Icons.notifications_outlined),
                                            label: Text(service
                                                    .enablingPhoneAlerts
                                                ? 'Enabling…'
                                                : service.phoneAlertsEnabled
                                                    ? 'Phone alerts on'
                                                    : 'Enable phone alerts')),
                                        if (service.phoneAlertError.isNotEmpty)
                                          Text(service.phoneAlertError),
                                      ])),
                            if (service.audience == 'CUSTOMER')
                              TextButton.icon(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const AlertsScreen())),
                                  icon: const Icon(Icons.timer_outlined),
                                  label: const Text('View rental timers')),
                            if (service.items.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final filterOption in const [
                                        'All',
                                        'Unread',
                                        'Rentals',
                                        'Chat',
                                      ])
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6),
                                          child: ChoiceChip(
                                            key: ValueKey(
                                                'notif-filter-$filterOption'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(filterOption),
                                            selected: _filter == filterOption,
                                            onSelected: (_) {
                                              HapticFeedback.selectionClick();
                                              setState(
                                                  () => _filter = filterOption);
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (service.error.isNotEmpty) ...[
                              RentalNotice(
                                  title: 'Could not refresh notifications',
                                  message: service.error),
                              OutlinedButton(
                                  onPressed: () => service.refresh(),
                                  child: const Text('Try again'))
                            ],
                            if (filteredItems.isEmpty && service.error.isEmpty)
                              RentalEmptyState(
                                  title: service.items.isEmpty
                                      ? 'No updates yet'
                                      : 'No matching notifications',
                                  message: service.items.isEmpty
                                      ? 'You will see rental requests, decisions and return updates here.'
                                      : 'Try switching the filter above or refreshing your inbox.'),
                            for (final row in filteredItems)
                              Dismissible(
                                key: ValueKey('notif-dismiss-${row.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  alignment: Alignment.centerRight,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(
                                    Icons.done_all_rounded,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                onDismissed: (_) {
                                  HapticFeedback.lightImpact();
                                  setState(() => _dismissedIds.add(row.id));
                                  if (!row.isRead) {
                                    service
                                        .markRead([row.id]).catchError((_) {});
                                  }
                                },
                                child: GlassCard(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    isSelected: !row.isRead,
                                    child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                        leading: Icon(
                                            row.type.contains('REJECTED')
                                                ? Icons.cancel_outlined
                                                : row.type.contains(
                                                            'APPROVED') ||
                                                        row.type.contains(
                                                            'COMPLETED')
                                                    ? Icons.check_circle_outline
                                                    : Icons
                                                        .receipt_long_outlined,
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
                                            padding:
                                                const EdgeInsets.only(top: 6),
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
                              ),
                            if (service.nextCursor != null)
                              OutlinedButton(
                                  onPressed: () => service.refresh(older: true),
                                  child: const Text('Load older updates')),
                          ])),
        ));
  }
}
