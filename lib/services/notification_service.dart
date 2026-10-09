import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/rental_notification.dart';
import 'mobile_api_service.dart';

class NotificationDevices {
  static String? token;
  static Future<void> _operations = Future.value();
  static Future<T> serial<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<void> unregister(MobileApiService api) => serial(() async {
        if (!supported) return;
        final previous = token;
        token = null;
        if (previous != null) {
          try {
            await api.unregisterNotificationDevice(previous);
          } catch (_) {}
        }
        try {
          await FirebaseMessaging.instance.deleteToken();
        } catch (_) {}
      });

  static Future<void> rotateForAccount(MobileApiService api) =>
      serial(() async {
        if (!supported) return;
        final previous = token;
        token = null;
        if (previous != null) {
          try {
            await api.unregisterNotificationDevice(previous);
          } catch (_) {}
        }
        // FCM tokens are installation-scoped. Replacing one on each account
        // change prevents a token registered by staff from staying active on
        // a device that is now signed in as a customer.
        try {
          await FirebaseMessaging.instance.deleteToken();
        } catch (_) {}
      });
}

class RentalNotificationService extends ChangeNotifier {
  RentalNotificationService({MobileApiService? api, this.pushEnabled = true})
      : _api = api ?? MobileApiService.instance;
  final MobileApiService _api;
  MobileApiService get api => _api;
  final bool pushEnabled;
  final _arrivals = StreamController<RentalNotification>.broadcast();
  final _opens = StreamController<String>.broadcast();
  Stream<RentalNotification> get arrivals => _arrivals.stream;
  Stream<String> get opens => _opens.stream;
  final Map<String, RentalNotification> _items = {};
  final Set<String> _seen = {};
  final Set<String> _readLocally = {};
  String? _uid, nextCursor, _revision;
  int _generation = 0;
  bool _pending = false,
      _initialized = false,
      _hasOlder = false,
      _disposed = false,
      _active = true;
  bool phoneAlertsEnabled = false, enablingPhoneAlerts = false;
  String error = '', phoneAlertError = '', audience = 'CUSTOMER';
  Timer? _poll;
  StreamSubscription<RemoteMessage>? _messages, _opened;
  StreamSubscription<String>? _tokens;
  bool get signedIn => _uid != null;
  bool get loading => _pending && !_initialized;
  bool get phoneAlertsSupported => pushEnabled && NotificationDevices.supported;
  int get unreadCount => _items.values.where((row) => !row.isRead).length;
  List<RentalNotification> get items => _items.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setSession(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    final version = ++_generation;
    _poll?.cancel();
    _pending = false;
    _initialized = false;
    _hasOlder = false;
    _items.clear();
    _seen.clear();
    _readLocally.clear();
    _revision = null;
    nextCursor = null;
    error = '';
    audience = 'CUSTOMER';
    phoneAlertsEnabled = false;
    enablingPhoneAlerts = false;
    phoneAlertError = '';
    Future.microtask(() async {
      if (_disposed || version != _generation) return;
      _notify();
      if (pushEnabled) await NotificationDevices.rotateForAccount(_api);
      if (_disposed || version != _generation) return;
      if (uid == null) return;
      await refresh();
      if (_disposed || version != _generation) return;
      _poll = Timer.periodic(const Duration(minutes: 2), (_) {
        if (_active) refresh();
      });
      await _setupPush();
    });
  }

  void setActive(bool active) {
    _active = active;
    if (active) refresh();
  }

  Future<void> refresh({bool older = false}) async {
    if (_disposed || _uid == null || _pending || older && nextCursor == null) {
      return;
    }
    final version = _generation;
    _pending = true;
    _notify();
    try {
      final response = await _api.notifications(
          before: older ? nextCursor : null, since: older ? null : _revision);
      if (_disposed || version != _generation) return;
      if (response['unchanged'] == true) {
        error = '';
        return;
      }
      if (!older) _revision = response['revision']?.toString();
      final incoming = (response['notifications'] as List? ?? [])
          .whereType<Map>()
          .map((row) =>
              RentalNotification.fromMap(Map<String, dynamic>.from(row)))
          .toList();
      final arrivals = _initialized && !older
          ? incoming
              .where((row) => !row.isRead && !_seen.contains(row.id))
              .toList()
          : <RentalNotification>[];
      if (!older && !_hasOlder) _items.clear();
      for (final row in incoming) {
        _items[row.id] = _readLocally.contains(row.id) ? row.read() : row;
        _seen.add(row.id);
      }
      if (older) _hasOlder = true;
      if (older || !_hasOlder) nextCursor = response['next_cursor']?.toString();
      audience = response['audience']?.toString() ?? 'CUSTOMER';
      _initialized = true;
      error = '';
      if (_active && arrivals.isNotEmpty) _arrivals.add(arrivals.first);
    } catch (problem) {
      if (!_disposed && version == _generation) error = '$problem';
    } finally {
      if (!_disposed && version == _generation) {
        _pending = false;
        _notify();
      }
    }
  }

  Future<void> markRead(Iterable<String> ids) async {
    final version = _generation;
    final chosen = ids.where((id) => _items[id]?.isRead == false).toList();
    for (var index = 0; index < chosen.length; index += 60) {
      final chunk = chosen.skip(index).take(60).toList();
      await _api.markNotificationsRead(chunk);
      if (_disposed || version != _generation) return;
      for (final id in chunk) {
        _readLocally.add(id);
        final row = _items[id];
        if (row != null) _items[id] = row.read();
      }
      _notify();
    }
  }

  Future<void> _setupPush() async {
    if (!phoneAlertsSupported || _uid == null) return;
    final version = _generation;
    try {
      _messages ??= FirebaseMessaging.onMessage.listen((_) => refresh());
      _opened ??= FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      _tokens ??=
          FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (_uid != null && phoneAlertsEnabled) {
          try {
            await _register(token);
          } catch (_) {}
        }
      });
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (_disposed || version != _generation) return;
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (allowed) {
        final token = await FirebaseMessaging.instance.getToken();
        if (_disposed || version != _generation) return;
        phoneAlertsEnabled = await _register(token);
      }
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (_disposed || version != _generation) return;
      if (message != null) _openMessage(message);
    } catch (_) {
      if (_disposed || version != _generation) return;
      phoneAlertError =
          'Phone alerts are unavailable. You can still read updates here.';
    }
    _notify();
  }

  void _openMessage(RemoteMessage message) {
    if (_uid == null) return;
    final recipient = message.data['recipient_id'];
    if (recipient != null && recipient.isNotEmpty && recipient != _uid) return;
    final messageAudience = message.data['audience'];
    if (messageAudience != null &&
        messageAudience.isNotEmpty &&
        messageAudience != audience) return;
    final id = message.data['notification_id'];
    if (id != null) _opens.add(id);
    refresh();
  }

  Future<bool> _register(String? token) async {
    if (token == null || _uid == null) return false;
    final version = _generation;
    return NotificationDevices.serial(() async {
      if (_disposed || version != _generation) return false;
      await _api.registerNotificationDevice(token);
      NotificationDevices.token = token;
      return !_disposed && version == _generation;
    });
  }

  Future<void> enablePhoneAlerts() async {
    if (!phoneAlertsSupported || _uid == null || enablingPhoneAlerts) return;
    final version = _generation;
    enablingPhoneAlerts = true;
    phoneAlertError = '';
    _notify();
    try {
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (_disposed || version != _generation) return;
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (allowed) {
        final token = await FirebaseMessaging.instance.getToken();
        if (_disposed || version != _generation) return;
        phoneAlertsEnabled = await _register(token);
        if (!phoneAlertsEnabled) {
          phoneAlertError = 'Could not enable phone alerts. Try again.';
        }
      } else {
        phoneAlertError =
            'Allow notifications in your phone settings to receive phone alerts.';
      }
    } catch (_) {
      if (!_disposed && version == _generation) {
        phoneAlertError = 'Could not enable phone alerts. Try again.';
      }
    } finally {
      if (!_disposed && version == _generation) {
        enablingPhoneAlerts = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
    _messages?.cancel();
    _opened?.cancel();
    _tokens?.cancel();
    _arrivals.close();
    _opens.close();
    super.dispose();
  }
}
