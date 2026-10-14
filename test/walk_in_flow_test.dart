import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'widget_test.dart' show SignedOutAuth;
import 'package:rent_and_play_app/screens/admin/walk_in_customer_form.dart';
import 'package:rent_and_play_app/screens/admin/rental_admin_view.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';

class WalkInApi extends MobileApiService {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> adminRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool forceRefresh = false}) async {
    calls.add({'path': path, ...?body});
    if (path == '/customers') {
      return {
        'customer': {
          'id': 'walkin',
          'full_name': 'Juan Dela Cruz',
          'phone': '09171234567',
          'customer_code': 'CUST-001',
          'is_active': true
        }
      };
    }
    if (path == '/pricing/quote') {
      return {
        'quote': {
          'rental_fee': 50,
          'billed_minutes': 60,
          'overtime_rate': 10,
          'overtime_unit_minutes': 60
        }
      };
    }
    if (path.endsWith('/release-verification')) {
      return {
        'rental': {'id': 'rental'},
        'rental_verified': true,
        'delivery_prepared': true
      };
    }
    return {
      'rental': {'id': 'rental', 'rental_code': 'R-0001'}
    };
  }
}

Finder field(String label) => find.widgetWithText(TextFormField, label);
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });
  testWidgets(
      'walk-in customer can be saved without email, password, or app access',
      (tester) async {
    final api = WalkInApi();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WalkInCustomerForm(api: api))));
    await tester.enterText(field('Full name'), 'Juan Dela Cruz');
    await tester.enterText(field('Philippine mobile number'), '09171234567');
    await tapVisible(tester, find.text('Save customer profile'));
    expect(api.calls.single['path'], '/customers');
    expect(api.calls.single['email'], '');
    expect(api.calls.single.containsKey('password'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'staff creates an approved shop rental for an existing customer with explicit fulfillment',
      (tester) async {
    final api = WalkInApi();
    await tester.pumpWidget(MaterialApp(
        home: RentalAdminActionScreen(
            api: api,
            row: const {},
            action: 'booking',
            workspace: const {
              'customers': [
                {
                  'id': 'walkin',
                  'full_name': 'Juan Dela Cruz',
                  'customer_code': 'CUST-001',
                  'phone': '09171234567',
                  'is_active': true
                }
              ],
              'items': [
                {
                  'id': 'unit',
                  'name': 'Basketball',
                  'item_code': 'EQUIP-001',
                  'status': 'AVAILABLE',
                  'is_active': true
                }
              ],
            })));
    await tapVisible(tester, find.text('Available equipment'));
    await tester.tap(find.text('Basketball · EQUIP-001').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Customer'));
    await tester.tap(find.text('Juan Dela Cruz · CUST-001').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Preview price'));
    expect(api.calls.last['path'], '/pricing/quote');
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Create walk-in rental'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    final saved = api.calls.last;
    expect(saved['path'], '/rental-bookings');
    expect(saved['customerId'], 'walkin');
    expect(saved['rentalChannel'], 'WALK_IN');
    expect(saved['fulfillmentMode'], 'SHOP_HANDOVER');
    expect(saved['deliveryLocation'], 'Rent & Play · Lakewoods, Los Baños');
    expect(saved.containsKey('paymentVerified'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'walk-in handover uses saved reference and requires witnessed customer agreement',
      (tester) async {
    final api = WalkInApi();
    await tester.pumpWidget(MaterialApp(
        home: RentalAdminActionScreen(
            api: api,
            row: const {
              'id': 'rental',
              'rental_code': 'R-0001',
              'request_source': 'WALK_IN',
              'fulfillment_mode': 'SHOP_HANDOVER',
              'status': 'APPROVED',
              'delivery_status': 'PREPARED',
              'item_name': 'Basketball',
              'customer_name': 'Juan Dela Cruz',
              'rental_fee': 50,
              'fee_breakdown': {
                'billed_minutes': 60,
                'overtime_rate': 10,
                'overtime_unit_minutes': 60
              },
            },
            action: 'release',
            workspace: const {})));
    expect(find.text('Rental reference'), findsOneWidget);
    await tapVisible(tester, find.text('Verify customer rental'));
    expect(api.calls.single['transactionCode'], 'R-0001');
    expect(api.calls.single['manualReason'], contains('walk-in'));
    for (final text in [
      'The receiver matches the rental customer.',
      'Rental payment received and verified',
      'I checked this unit and all included accessories.'
    ]) {
      await tapVisible(tester, find.text(text));
    }
    await tester.ensureVisible(field('Inspection notes'));
    await tester.enterText(
        field('Inspection notes'), 'Unit works and accessories are complete.');
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Confirm shop handover'));
    expect(api.calls.length, 1);
    expect(find.textContaining('Confirm that the customer agreed'),
        findsOneWidget);
    await tapVisible(
        tester,
        find.text(
            'Customer agreed to the duration, total, late fees, and physical return inspection.'));
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Confirm shop handover'));
    expect(api.calls.last['path'], '/rentals/rental/release');
    expect(api.calls.last['customerTermsAcknowledged'], true);
    expect(api.calls.last['customerVerified'], true);
    expect(api.calls.last['paymentVerified'], true);
    expect(tester.takeException(), isNull);
  });
}
