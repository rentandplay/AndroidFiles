import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rental_notification.dart';
import '../services/notification_service.dart';
import '../screens/alerts/notifications_screen.dart';

final rentalNavigatorKey = GlobalKey<NavigatorState>();
final rentalMessengerKey = GlobalKey<ScaffoldMessengerState>();

class RentalNotificationBell extends StatelessWidget {
  const RentalNotificationBell({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final count = context.watch<RentalNotificationService?>()?.unreadCount ?? 0;
    return IconButton(
        tooltip: count > 0 ? '$count unread notifications' : 'Notifications',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen())),
        icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: Icon(Icons.notifications_outlined, color: color, size: 22)));
  }
}

class RentalNotificationHost extends StatefulWidget {
  const RentalNotificationHost({super.key, required this.child});
  final Widget child;
  @override
  State<RentalNotificationHost> createState() => _RentalNotificationHostState();
}

class _RentalNotificationHostState extends State<RentalNotificationHost>
    with WidgetsBindingObserver {
  RentalNotificationService? _service;
  StreamSubscription<RentalNotification>? _arrivals;
  StreamSubscription<String>? _opens;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<RentalNotificationService>();
    if (identical(service, _service)) return;
    _arrivals?.cancel();
    _opens?.cancel();
    _service = service;
    _arrivals = service.arrivals.listen((row) {
      rentalMessengerKey.currentState?.showSnackBar(SnackBar(
          content: Text('${row.title}\n${row.message}'),
          duration: const Duration(seconds: 6),
          action:
              SnackBarAction(label: 'View', onPressed: () => _open(row.id))));
    });
    _opens = service.opens.listen(_open);
  }

  void _open(String id) {
    rentalNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => NotificationsScreen(initialId: id)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service?.setActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _arrivals?.cancel();
    _opens?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
