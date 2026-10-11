import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rent_and_play_app/models/rental_model.dart';
import 'package:rent_and_play_app/screens/admin/admin_dashboard_screen.dart';
import 'package:rent_and_play_app/screens/user/active_rentals_screen.dart';
import 'package:rent_and_play_app/services/admin_firestore_service.dart';
import 'package:rent_and_play_app/services/auth_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';

import 'widget_test.dart' show SignedOutAuth;

class _Customer extends Fake implements User {
  @override
  String get uid => 'customer';
}

class _CustomerAuth extends AuthService {
  final User _user = _Customer();
  @override
  User? get currentUser => _user;
}

RentalModel rental(String status) => RentalModel(
      rentalId: 'rental-1',
      itemId: 'bike',
      itemName: 'Bicycle',
      customerId: 'customer',
      customerName: 'Customer',
      terminalId: '',
      startDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(hours: 3)),
      rateFee: 150,
      paymentMethod: 'CASH',
      status: status,
      rentalCode: 'R-001',
    );

class _RentalApi extends MobileApiService {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  List<RentalModel> rentals = [rental('PENDING_ADMIN_APPROVAL')];
  int calls = 0;
  Completer<List<RentalModel>>? pending;
  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => events.stream;
  @override
  Future<List<RentalModel>> listRentals() async {
    calls++;
    final delayed = pending;
    pending = null;
    return delayed == null ? rentals : await delayed.future;
  }
}

class _StaffApi extends AdminFirestoreService {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  int calls = 0, available = 1;
  bool failRestore = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  bool get hasSession => true;
  @override
  Map<String, dynamic> get currentUser =>
      {'id': 'operator', 'name': 'Operator', 'role': 'OPERATOR'};
  @override
  Future<Map<String, dynamic>> restoreAdminSession() async {
    if (failRestore) {
      throw const AdminApiException('Service temporarily unavailable',
          statusCode: 503);
    }
    return currentUser;
  }

  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => events.stream;
  Map<String, dynamic> get workspace => {
        'transactions': [],
        'items': [],
        'customers': [],
        '_dashboard': {
          'rentals': [],
          'stats': {'available': available}
        },
      };
  @override
  Future<Map<String, dynamic>> loadWorkspace(
      {bool forceRefresh = false}) async {
    calls++;
    final delayed = pending;
    pending = null;
    return delayed == null ? workspace : await delayed.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });

  testWidgets(
      'customer progress follows approval, release and receipt events without a refresh',
      (tester) async {
    final api = _RentalApi(), auth = _CustomerAuth();
    final semantics = tester.ensureSemantics();
    addTearDown(auth.dispose);
    addTearDown(api.events.close);
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(home: ActiveRentalsScreen(api: api)),
    ));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Rental progress: Request stage')),
        findsOneWidget);
    for (final step in [
      ('APPROVED', 'Handoff'),
      ('ACTIVE', 'In use'),
      ('RETURN_PENDING_INSPECTION', 'Return'),
    ]) {
      api.rentals = [rental(step.$1)];
      api.events.add({'event': 'rental.changed', 'rentalId': 'rental-1'});
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Rental progress: ${step.$2} stage')),
          findsOneWidget);
    }
    api.rentals = [rental('COMPLETED')];
    api.events.add({'event': 'rental.changed', 'rentalId': 'rental-1'});
    await tester.pumpAndSettle();
    expect(find.byType(RentalBookingCard), findsNothing);
    expect(api.calls, 5);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets(
      'a live change during a customer fetch is not overwritten by its older response',
      (tester) async {
    final api = _RentalApi()..pending = Completer<List<RentalModel>>();
    final delayed = api.pending!;
    final auth = _CustomerAuth();
    addTearDown(auth.dispose);
    addTearDown(api.events.close);
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
      value: auth,
      child: MaterialApp(home: ActiveRentalsScreen(api: api)),
    ));
    await tester.pump();
    api.rentals = [rental('ACTIVE')];
    api.events.add({'event': 'rental.changed', 'rentalId': 'rental-1'});
    await tester.pump();
    delayed.complete([rental('PENDING_ADMIN_APPROVAL')]);
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(
        tester
            .widget<RentalBookingCard>(find.byType(RentalBookingCard))
            .rental
            .status,
        'ACTIVE');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'staff coalesces live bursts, resyncs on reconnect and pauses background reads',
      (tester) async {
    final api = _StaffApi();
    addTearDown(api.events.close);
    await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(api: api, onSignedOut: () {})));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    for (var i = 0; i < 5; i++) {
      api.events.add({'event': 'rental.changed'});
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    await tester.pump(const Duration(minutes: 2));
    expect(api.calls, 2);
    api.events.add({'event': 'ready'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(api.calls, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(api.events.hasListener, isFalse);
    await tester.pump(const Duration(minutes: 6));
    expect(api.calls, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.calls, 4);
    expect(api.events.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'staff queues a change arriving while a workspace fetch is in progress',
      (tester) async {
    final api = _StaffApi();
    addTearDown(api.events.close);
    await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(api: api, onSignedOut: () {})));
    await tester.pumpAndSettle();
    final delayed = Completer<Map<String, dynamic>>();
    api.pending = delayed;
    api.events.add({'event': 'rental.changed'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(api.calls, 2);
    api.available = 2;
    api.events.add({'event': 'rental.changed'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    delayed.complete({
      'transactions': [],
      '_dashboard': {
        'rentals': [],
        'stats': {'available': 1}
      }
    });
    await tester.pumpAndSettle();
    expect(api.calls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'staff recovers through live events after the initial session request fails',
      (tester) async {
    final api = _StaffApi()..failRestore = true;
    addTearDown(api.events.close);
    await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(api: api, onSignedOut: () {})));
    await tester.pumpAndSettle();
    expect(api.calls, 0);
    expect(api.events.hasListener, isTrue);
    api.failRestore = false;
    api.events.add({'event': 'ready'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
