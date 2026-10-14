import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:rent_and_play_app/services/admin_api_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/screens/admin/payments_screen.dart';
import 'package:rent_and_play_app/screens/admin/money_entry_dialog.dart';
import 'package:rent_and_play_app/screens/admin/rental_extra_screen.dart';
import 'package:rent_and_play_app/screens/admin/delivery_calendar_screen.dart';
import 'package:rent_and_play_app/screens/shared/rental_extension_dialog.dart';
import 'widget_test.dart' show SignedOutAuth;

class PaymentApi extends AdminFirestoreService {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> getMap(String path,
          {bool forceRefresh = false}) async =>
      path.startsWith('/finance/summary')
          ? {
              'totals': {'collections': 40, 'cash_net_movement': 30}
            }
          : {'entries': [], 'nextCursor': null};
  @override
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic> body = const {}}) async {
    calls.add({'path': path, ...body});
    return path == '/rentals/lookup'
        ? {
            'rental': {
              'id': 'rental',
              'rental_code': 'R-0001',
              'customer_name': 'Customer',
              'item_name': 'Bicycle',
              'status': 'PENDING_ADMIN_APPROVAL',
              'balance_due': 60
            }
          }
        : {};
  }
}

class ExtraApi extends MobileApiService {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> adminRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool forceRefresh = false}) async {
    calls.add({'path': path, ...?body});
    if (path.startsWith('/records/rentals')) {
      return {
        'records': [
          {
            'id': 'rental',
            'rental_code': 'R-0001',
            'item_name': 'Bicycle',
            'customer_name': 'Customer',
            'scheduled_start_at': '2026-10-15T02:00:00Z',
            'status': 'APPROVED',
            'delivery_status': 'OUT_FOR_DELIVERY',
            'delivery_location': 'Lakewood resort'
          }
        ],
        'nextCursor': null
      };
    }
    return path.endsWith('extension-quote')
        ? {
            'quote': {
              'additional_fee': 100,
              'billed_minutes': 60,
              'due_at': '2026-10-15T06:00:00Z'
            }
          }
        : {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });
  Future<void> field(WidgetTester tester, String label, String value) async {
    final finder = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, PaymentApi api,
      {bool receipt = false}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            MoneyEntryDialog(api: api, receipt: receipt)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'partial cash receipt requires matching rental and actual receipt confirmation, without approving it',
      (tester) async {
    final api = PaymentApi();
    await open(tester, api, receipt: true);
    await field(tester, 'Rental reference', 'R-0001');
    await tester.tap(find.text('Find rental'));
    await tester.pumpAndSettle();
    await field(tester, 'Amount received (PHP)', '40');
    await field(tester, 'Description / notes', 'Cash received in person');
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    expect(
        api.calls.where((row) => row['path'].toString().endsWith('settlement')),
        isEmpty);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    final row = api.calls.last;
    expect(row['path'], '/rentals/rental/settlement');
    expect(row['paymentAmount'], 40);
    expect(row['paymentMethod'], 'CASH');
    expect(row.containsKey('action'), false);
    expect(row['requestKey'].toString().length, 32);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cash expense validates the paid amount and summary fits a narrow phone',
      (tester) async {
    final api = PaymentApi();
    await open(tester, api);
    await field(tester, 'Amount paid (PHP)', '1.234');
    await field(tester, 'Description / notes', 'Paper roll');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await field(tester, 'Amount paid (PHP)', '10.25');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(api.calls.single['amount'], 10.25);
    expect(api.calls.single['path'], '/finance/expenses');
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: PaymentsScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Net cash recorded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'extension is quoted before the customer agrees to the exact additional price',
      (tester) async {
    final api = ExtraApi();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () =>
                        showRentalExtensionDialog(context, api, 'rental'),
                    child: const Text('Extend'))))));
    await tester.tap(find.text('Extend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review price'));
    await tester.pumpAndSettle();
    expect(api.calls.single['path'], '/mobile/rentals/rental/extension-quote');
    expect(find.text('Additional charge: ₱100.00'), findsOneWidget);
    await tester.tap(find.text('Agree & request extension'));
    await tester.pumpAndSettle();
    expect(api.calls.last['expectedAdditionalFee'], 100);
    expect(api.calls.last['requestKey'], api.calls.first['requestKey']);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'unsuccessful delivery receives the scanned unit at the shop with a damage description',
      (tester) async {
    final api = ExtraApi();
    await tester.pumpWidget(MaterialApp(
        home: RentalExtraScreen(row: const {
      'id': 'rental',
      'rental_code': 'R-0001',
      'item_name': 'Bicycle',
      'delivery_location': 'Lakewood resort',
      'delivery_status': 'DELIVERY_FAILED'
    }, kind: 'delivery', api: api, scannedCode: 'rp-unit')));
    await tester.pumpAndSettle();
    expect(find.text('rp-unit'), findsOneWidget);
    await tester.tap(find.text('GOOD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DAMAGED').last);
    await tester.pumpAndSettle();
    final notes =
        find.widgetWithText(TextField, 'Condition notes (required for damage)');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Brake cable damaged');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(find.text('Confirm'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(api.calls.single['inventoryCode'], 'rp-unit');
    expect(api.calls.single['condition'], 'DAMAGED');
    expect(api.calls.single['notes'], 'Brake cable damaged');
    expect(api.calls.single['physicalReceiptConfirmed'], true);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'staff-assisted extension requires customer agreement and uses the shared rental endpoints',
      (tester) async {
    final api = ExtraApi();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showRentalExtensionDialog(
                        context, api, 'rental',
                        staff: true),
                    child: const Text('Extend'))))));
    await tester.tap(find.text('Extend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review price'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree & request extension'));
    await tester.pumpAndSettle();
    expect(api.calls.length, 1);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Agree & request extension'));
    await tester.pumpAndSettle();
    expect(api.calls.last['path'], '/rentals/rental/extension');
    expect(api.calls.last['customerRequestedExtension'], true);
    expect(api.calls.last['expectedAdditionalFee'], 100);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'mobile delivery calendar fetches bounded schedules for the selected Philippine day',
      (tester) async {
    final api = ExtraApi();
    await tester
        .pumpWidget(MaterialApp(home: DeliveryCalendarScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('R-0001 · Bicycle'), findsOneWidget);
    expect(find.textContaining('On the way'), findsOneWidget);
    final query = Uri.parse(api.calls.single['path']).queryParameters;
    expect(query['status'], 'OPEN');
    expect(query['limit'], '25');
    expect(
        query['scheduledDay'],
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String()
            .substring(0, 10));
    expect(tester.takeException(), isNull);
  });
}
