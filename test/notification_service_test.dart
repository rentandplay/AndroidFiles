import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/services/notification_service.dart';
import 'widget_test.dart' show SignedOutAuth;

Map<String, dynamic> event(String id) => {
      'id': id,
      'type': 'BOOKING_APPROVED',
      'title': 'Booking approved',
      'message': 'Equipment handoff is ready.',
      'rental_id': 'r1',
      'rental_code': 'R-001',
      'created_at': '2026-10-07T02:00:00Z',
      'is_read': false,
    };

class NotificationsApi extends MobileApiService {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => events.stream;
  List<Map<String, dynamic>> incoming = [event('one')];
  bool failFetch = false, failRead = false;
  String? lastSince;
  Completer<Map<String, dynamic>>? delayed;
  final reads = <String>[];
  @override
  Future<Map<String, dynamic>> notifications(
      {String? before, String? since}) async {
    lastSince = since;
    if (failFetch) throw const MobileApiException('Connection interrupted');
    if (delayed != null) return delayed!.future;
    return {
      'notifications': incoming,
      'revision': 'revision-1',
      'audience': 'CUSTOMER'
    };
  }

  @override
  Future<void> markNotificationsRead(List<String> ids) async {
    if (failRead) throw const MobileApiException('Could not save read status');
    reads.addAll(ids);
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });
  test(
      'history stays silent, new updates alert once and polls send an inbox revision',
      () async {
    final api = NotificationsApi();
    final inbox = RentalNotificationService(api: api, pushEnabled: false);
    addTearDown(inbox.dispose);
    final alerts = <String>[];
    final subscription = inbox.arrivals.listen((row) => alerts.add(row.id));
    addTearDown(subscription.cancel);
    inbox.setSession('customer');
    await flush();
    expect(inbox.unreadCount, 1);
    expect(alerts, isEmpty);
    api.incoming = [event('two'), event('one')];
    await inbox.refresh();
    await flush();
    await inbox.refresh();
    await flush();
    expect(alerts, ['two']);
    expect(inbox.unreadCount, 2);
    expect(api.lastSince, 'revision-1');
  });
  test('late responses cannot restore a previous account inbox', () async {
    final api = NotificationsApi()..delayed = Completer();
    final inbox = RentalNotificationService(api: api, pushEnabled: false);
    addTearDown(inbox.dispose);
    inbox.setSession('customer-one');
    await flush();
    inbox.setSession(null);
    api.delayed!.complete({
      'notifications': [event('private')]
    });
    await flush();
    expect(inbox.signedIn, isFalse);
    expect(inbox.items, isEmpty);
  });
  test(
      'reading survives an older in-flight fetch and failed refresh preserves history',
      () async {
    final api = NotificationsApi();
    final service = RentalNotificationService(api: api, pushEnabled: false);
    addTearDown(service.dispose);
    service.setSession('customer');
    await flush();
    api.delayed = Completer();
    final pending = service.refresh();
    await service.markRead(['one']);
    api.delayed!.complete({
      'notifications': [event('one')],
      'revision': 'revision-1'
    });
    await pending;
    expect(service.unreadCount, 0);
    expect(api.reads, ['one']);
    api.delayed = null;
    api.failFetch = true;
    await service.refresh();
    expect(service.items.length, 1);
    expect(service.error, 'Connection interrupted');
  });
  test('failed read requests retain unread status and can be retried',
      () async {
    final api = NotificationsApi()..failRead = true;
    final service = RentalNotificationService(api: api, pushEnabled: false);
    addTearDown(service.dispose);
    service.setSession('customer');
    await flush();
    await expectLater(
        service.markRead(['one']), throwsA(isA<MobileApiException>()));
    expect(service.unreadCount, 1);
    api.failRead = false;
    await service.markRead(['one']);
    expect(service.unreadCount, 0);
  });
  test(
      'live rental events deliver mobile alerts once and reconnect resyncs missed notifications',
      () async {
    final api = NotificationsApi();
    final service = RentalNotificationService(api: api, pushEnabled: false);
    addTearDown(api.events.close);
    addTearDown(service.dispose);
    final alerts = <String>[];
    final subscription = service.arrivals.listen((row) => alerts.add(row.id));
    addTearDown(subscription.cancel);
    service.setSession('customer');
    await flush();
    api.incoming = [event('two'), event('one')];
    api.events.add({'event': 'rental.changed'});
    await flush();
    await flush();
    expect(alerts, ['two']);
    expect(service.unreadCount, 2);
    api.events.add({'event': 'rental.changed'});
    await flush();
    await flush();
    expect(alerts, ['two']);
    service.setActive(false);
    api.incoming = [event('three'), ...api.incoming];
    api.events.add({'event': 'rental.changed'});
    await flush();
    expect(service.unreadCount, 2);
    service.setActive(true);
    await flush();
    await flush();
    api.events.add({'event': 'ready'});
    await flush();
    await flush();
    expect(alerts, ['two', 'three']);
    expect(service.unreadCount, 3);
  });
}
