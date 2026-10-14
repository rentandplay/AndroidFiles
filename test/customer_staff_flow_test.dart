import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rent_and_play_app/models/item_model.dart';
import 'package:rent_and_play_app/models/rental_model.dart';
import 'package:rent_and_play_app/services/auth_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/screens/admin/rental_admin_view.dart';
import 'package:rent_and_play_app/screens/user/checkout_screen.dart';
import 'package:rent_and_play_app/screens/user/active_rentals_screen.dart';
import 'widget_test.dart' show SignedOutAuth;

class _Customer extends Fake implements User {
  @override
  String get uid => 'customer';
}

class _CustomerAuth extends AuthService {
  @override
  User? get currentUser => _Customer();
}

class _FlowApi extends MobileApiService {
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic> row = {
    'id': 'rental',
    'rental_code': 'R-0001',
    'item_id': 'unit',
    'item_name': 'Jenga',
    'customer_id': 'customer',
    'customer_name': 'Customer',
    'status': 'PENDING_ADMIN_APPROVAL',
    'rental_fee': 150,
    'payment_method': 'CASH',
    'delivery_location': 'Shop pickup',
    'hold_expires_at': DateTime.now()
        .add(const Duration(minutes: 15))
        .toUtc()
        .toIso8601String(),
    'start_at': null,
    'due_at': null,
  };
  @override
  Future<Map<String, dynamic>> quoteRental(String id, int minutes,
          {String? stockGroupId, DateTime? scheduledStartAt}) async =>
      {
        'rental_fee': 150,
        'billed_minutes': 300,
        'requested_minutes': minutes,
        'overtime_rate': 30
      };
  @override
  Future<Map<String, dynamic>> paymentInstructions() async => {};
  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => const Stream.empty();
  @override
  Future<List<RentalModel>> listRentals() async => [RentalModel.fromMap(row)];
  @override
  Future<Map<String, dynamic>> rentalRecord(String id) async => Map.from(row);
  @override
  Future<RentalModel> createRentalRequest({
    required String itemId,
    String? stockGroupId,
    required String itemName,
    String? itemCode,
    required int durationMinutes,
    DateTime? scheduledStartAt,
    required String deliveryLocation,
    required String paymentMethod,
    required String requestKey,
    required Map<String, dynamic> expectedQuote,
    required bool acceptedRentalTerms,
    required String rentalTermsVersion,
    String? paymentProofImageDataUrl,
    String? paymentReference,
  }) async {
    calls.add({
      'itemId': itemId,
      'requestKey': requestKey,
      'durationMinutes': durationMinutes,
      'deliveryLocation': deliveryLocation,
      'paymentMethod': paymentMethod,
      'expectedQuote': expectedQuote,
      'acceptedRentalTerms': acceptedRentalTerms,
      'rentalTermsVersion': rentalTermsVersion
    });
    row = {...row, 'delivery_location': deliveryLocation};
    return RentalModel.fromMap(row);
  }

  @override
  Future<Map<String, dynamic>> adminRequest(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool forceRefresh = false,
  }) async {
    calls.add({'path': path, 'method': method, ...?body});
    if (method == 'POST' && body?['action'] == 'APPROVE') {
      row = {...row, 'status': 'APPROVED'};
    }
    return {'rental': row};
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
      'customer accepts the agreement, submits a cash rental and sees its saved request',
      (tester) async {
    final api = _FlowApi(), auth = _CustomerAuth();
    addTearDown(auth.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = ItemModel(
        id: 'unit',
        name: 'Jenga',
        category: 'Board Games',
        description: 'Complete set',
        rateText: '₱150 / 5 hours',
        rateHourly: 30,
        imageUrl: 'assets/images/logo_rent_and_play.png');
    await tester.pumpWidget(ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(home: CheckoutScreen(item: item, api: api))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Send rental request');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final location = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(location);
    await tester.tap(location);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASRI Hotspring Resort').last);
    await tester.pumpAndSettle();
    expect(find.text('Delivery to ASRI Hotspring Resort'), findsOneWidget);
    expect(find.text('Pick up at Rent & Play'), findsNothing);
    final agreement = find.byKey(const ValueKey('rental-terms-acceptance'));
    await tester.ensureVisible(agreement);
    await tester.tap(agreement);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(1));
    expect(api.calls.single['itemId'], 'unit');
    expect(api.calls.single['acceptedRentalTerms'], true);
    expect(api.calls.single['rentalTermsVersion'], mobileRentalTermsVersion);
    expect(api.calls.single['paymentMethod'], 'CASH');
    expect(api.calls.single['deliveryLocation'], 'ASRI Hotspring Resort');
    expect(api.calls.single['requestKey'], matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(find.byType(ActiveRentalsScreen), findsOneWidget);
    expect(find.text('R-0001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'staff approves the exact customer request without starting the rental timer',
      (tester) async {
    final api = _FlowApi();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => RentalAdminActionScreen(
                                row: api.row,
                                action: 'approve',
                                workspace: const {},
                                api: api))),
                    child: const Text('Review request'))))));
    await tester.tap(find.text('Review request'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Approve rental request'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(api.calls.single['path'], '/mobile/rentals/rental/review');
    expect(api.calls.single['method'], 'POST');
    expect(api.calls.single['action'], 'APPROVE');
    expect(api.row['status'], 'APPROVED');
    expect(api.row['start_at'], isNull);
    expect(api.row['rental_code'], 'R-0001');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
