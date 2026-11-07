import 'dart:async';
import 'package:flutter/foundation.dart';
import 'mobile_api_service.dart';
import 'server_clock.dart';

class BusinessSettings extends ChangeNotifier {
  BusinessSettings(this.api) {
    _events = api.watchRentalEvents().listen((event) {
      if (event['event'] == 'ready' || event['event'] == 'settings.changed') {
        refresh();
      }
    });
    refresh();
  }
  final MobileApiService api;
  StreamSubscription<Map<String, dynamic>>? _events;
  Map<String, dynamic> values = {};
  String error = '';
  bool loaded = false, _disposed = false;
  int _version = 0;
  Future<void> refresh() async {
    final version = ++_version;
    try {
      final result = await api.businessSettings();
      if (_disposed || version != _version) return;
      values = Map<String, dynamic>.from(result['settings'] as Map);
      loaded = true;
      error = '';
    } catch (_) {
      if (_disposed || version != _version) return;
      error = 'Could not refresh store details. Please try again.';
    }
    notifyListeners();
  }

  bool get openNow => isOpen(ServerClock.instance.now);
  bool isOpen(DateTime at) => withinStoreHours(at, values);
  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    super.dispose();
  }
}

// The mobile service operates in Asia/Manila (UTC+8, with no DST).
bool withinStoreHours(DateTime at, Map<String, dynamic> settings) {
  int minutes(String key, String fallback) {
    final parts = (settings[key] ?? fallback).toString().split(':');
    if (parts.length != 2) return -1;
    final hour = int.tryParse(parts[0]), minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return -1;
    }
    return hour * 60 + minute;
  }

  final local = at.toUtc().add(const Duration(hours: 8));
  final now = local.hour * 60 + local.minute;
  final opens = minutes('opens_at', '08:00'),
      closes = minutes('closes_at', '20:00');
  if (opens < 0 || closes < 0) return false;
  return opens == closes ||
      (opens < closes
          ? now >= opens && now < closes
          : now >= opens || now < closes);
}

String formatBusinessTime(dynamic value) {
  final parts = (value ?? '').toString().split(':');
  final hour = int.tryParse(parts.first);
  if (parts.length != 2 || hour == null) return 'Not available';
  return '${hour % 12 == 0 ? 12 : hour % 12}:${parts[1]} ${hour < 12 ? 'AM' : 'PM'}';
}
