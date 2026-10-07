import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rent_and_play_app/models/item_model.dart';
import 'package:rent_and_play_app/models/rental_model.dart';
import 'package:rent_and_play_app/screens/admin/rental_admin_view.dart';
import 'package:rent_and_play_app/screens/user/checkout_screen.dart';
import 'package:rent_and_play_app/screens/user/active_rentals_screen.dart';
import 'package:rent_and_play_app/screens/user/return_equipment_screen.dart';
import 'package:rent_and_play_app/screens/shared/transaction_ticket_dialog.dart';
import 'package:rent_and_play_app/screens/alerts/notifications_screen.dart';
import 'package:rent_and_play_app/services/notification_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/services/release_verification.dart';
import 'package:rent_and_play_app/theme/app_theme.dart';
import 'widget_test.dart' show SignedOutAuth;

class UiApi extends MobileApiService {
  Completer<Map<String, dynamic>>? pendingQuote;
  bool failQuote = false, failTicket = false;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> notifications(
          {String? before, String? since}) async =>
      {
        'revision': 'ui-notifications',
        'audience': 'CUSTOMER',
        'notifications': [
          {
            'id': 'rejected',
            'type': 'BOOKING_REJECTED',
            'title': 'Booking rejected',
            'message':
                'Your booking for Jenga was rejected. Reason: Equipment unavailable at the selected resort.',
            'rental_id': 'r-rejected',
            'rental_code': 'R-1024',
            'created_at': '2026-10-07T02:30:00Z',
            'is_read': false
          },
          {
            'id': 'approved',
            'type': 'BOOKING_APPROVED',
            'title': 'Booking approved',
            'message':
                'Your booking for Bicycle is approved. Keep your transaction QR ready for equipment handoff.',
            'rental_id': 'r-approved',
            'rental_code': 'R-1023',
            'created_at': '2026-10-07T02:00:00Z',
            'is_read': false
          }
        ]
      };
  @override
  Future<void> markNotificationsRead(List<String> ids) async {
    requests.add({'read_ids': ids});
  }

  @override
  Future<Map<String, dynamic>> rentalRecord(String id) async {
    requests.add({'rental_id': id});
    return {
      'id': id,
      'status': 'REJECTED',
      'item_name': 'Jenga',
      'customer_id': 'c1',
      'rental_code': 'R-1024',
      'rental_fee': 150,
      'deposit_amount': 100,
      'delivery_location': 'ASRI Hotspring Resort',
      'final_reason': 'Equipment unavailable at the selected resort.'
    };
  }

  @override
  Future<Map<String, dynamic>> quoteRental(String id, int minutes) async {
    if (failQuote) {
      throw const MobileApiException('Price service unavailable. Try again.');
    }
    if (pendingQuote != null) return pendingQuote!.future;
    return {'rental_fee': 150, 'deposit_amount': 100, 'billed_minutes': 300};
  }

  @override
  Future<Map<String, dynamic>> rentalTicket(String id) async {
    if (failTicket) {
      throw const MobileApiException('Ticket service unavailable.');
    }
    return {
      'status': 'PENDING_ADMIN_APPROVAL',
      'rental_code': 'R-123456',
      'hold_expires_at':
          DateTime.now().add(const Duration(minutes: 15)).toIso8601String()
    };
  }

  @override
  Future<Map<String, dynamic>> adminRequest(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    requests.add({'path': path, ...?body});
    if (body?['transactionCode'] != 'booking-qr') {
      throw const MobileApiException('This QR belongs to another booking.');
    }
    if (body?['inventoryCode'] != null && body?['inventoryCode'] != 'unit-qr') {
      throw const MobileApiException('Scan the assigned unit RENT-001.');
    }
    return {
      'rental': {'id': 'r1'},
      'booking_verified': true,
      'inventory_verified': body?['inventoryCode'] != null,
      'item': {'name': 'Jenga', 'item_code': 'RENT-001'}
    };
  }
}

final item = ItemModel(
    id: 'i1',
    name: 'Jenga',
    category: 'Board Games',
    description: 'Classic stacking game',
    rateText: '₱150 / 5 hours',
    rateHourly: 30,
    deposit: 100,
    imageUrl: 'assets/images/logo_rent_and_play.png');
RentalModel sampleRental(String status) => RentalModel(
      rentalId: 'r1',
      rentalCode: 'R-123456',
      itemId: 'i1',
      itemName: 'Jenga',
      customerId: 'c1',
      customerName: 'Demo Customer',
      terminalId: '',
      startDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(hours: 5)),
      rateFee: 150,
      deposit: 100,
      paymentMethod: 'Cash',
      status: status,
      holdExpiresAt: DateTime.now().add(const Duration(minutes: 30)),
      receivedAt: status == 'RETURN_PENDING_INSPECTION' ? DateTime.now() : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
    // Use the app's Material font for readable exported test renders.
    final fontDir = Directory('C:/flutter/bin/cache/artifacts/material_fonts');
    if (fontDir.existsSync()) {
      final loader = FontLoader('Roboto');
      for (final file in fontDir.listSync().whereType<File>().where((file) =>
          file.path.endsWith('.ttf') && file.path.contains('roboto-'))) {
        loader.addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())));
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(
            await File('${fontDir.path}/materialicons-regular.otf')
                .readAsBytes())));
      await icons.load();
    }
  });

  Future<void> render(WidgetTester tester, Widget screen,
      {bool dark = false,
      double width = 320,
      double scale = 1.3,
      GlobalKey? capture}) async {
    tester.view.physicalSize = Size(width, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: (dark ? AppTheme.darkTheme : AppTheme.lightTheme).copyWith(
              textTheme: (dark ? AppTheme.darkTheme : AppTheme.lightTheme)
                  .textTheme
                  .apply(fontFamily: 'Roboto')),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: screen,
        )));
    await tester.pump();
  }

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'checkout keeps booking action visible, shows package minimum, and never invents a zero price',
      (tester) async {
    final api = UiApi()..pendingQuote = Completer();
    final capture = GlobalKey();
    await render(tester, CheckoutScreen(item: item, api: api),
        capture: capture);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send booking request'))
            .onPressed,
        isNull);
    expect(find.text('₱0.00'), findsNothing);
    api.pendingQuote!.complete(
        {'rental_fee': 150, 'deposit_amount': 100, 'billed_minutes': 300});
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Send booking request');
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(780));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await save(tester, capture, 'android-checkout');
    await tester.scrollUntilVisible(find.text('Price summary'), 180);
    expect(find.textContaining('minimum package duration'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'release verifies the booking before equipment and refuses a mismatched unit',
      (tester) async {
    final api = UiApi(), capture = GlobalKey();
    await render(
        tester,
        RentalAdminActionScreen(
          row: const {
            'id': 'r1',
            'status': 'APPROVED',
            'item_name': 'Jenga',
            'customer_name': 'Demo Customer',
            'item_code': 'RENT-001',
            'rental_code': 'R-123456',
            'rental_fee': 150,
            'deposit_amount': 100
          },
          action: 'release',
          workspace: const {},
          api: api,
        ),
        dark: true,
        capture: capture);
    await tester.pumpAndSettle();
    expect(find.text('Equipment inventory QR'), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer transaction QR'),
        'wrong-booking');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify booking'));
    await tester.pumpAndSettle();
    expect(find.text('This QR belongs to another booking.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer transaction QR'),
        'booking-qr');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify booking'));
    await tester.pumpAndSettle();
    expect(find.text('Equipment inventory QR'), findsOneWidget);
    expect(find.text('Rental payment received and verified'), findsNothing);
    await save(tester, capture, 'android-admin-scan');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Equipment inventory QR'),
        'wrong-unit');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify equipment'));
    await tester.pumpAndSettle();
    expect(find.text('Scan the assigned unit RENT-001.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Equipment inventory QR'),
        'unit-qr');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify equipment'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm the handoff'), findsOneWidget);
    expect(
        api.requests.every((request) =>
            request['path'].toString().endsWith('/release-verification')),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('status cards fit narrow screens with large text in both themes',
      (tester) async {
    for (final dark in [false, true]) {
      for (final status in [
        'PENDING_ADMIN_APPROVAL',
        'APPROVED',
        'ACTIVE',
        'RETURN_PENDING_INSPECTION'
      ]) {
        await render(
            tester,
            Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: RentalBookingCard(
                            rental: sampleRental(status),
                            onTicket: () {},
                            onCancel: () {},
                            onReturn: () {})))),
            dark: dark);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$status / dark=$dark');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('return action stays usable above the keyboard', (tester) async {
    await render(tester,
        ReturnEquipmentScreen(rental: sampleRental('ACTIVE'), api: UiApi()),
        dark: true);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Send return request');
    expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('price errors leave booking disabled and allow a clear retry',
      (tester) async {
    final api = UiApi()..failQuote = true;
    await render(tester, CheckoutScreen(item: item, api: api));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send booking request'))
            .onPressed,
        isNull);
    expect(find.text('₱0.00'), findsNothing);
    await tester.scrollUntilVisible(find.text('Retry price'), 150);
    api.failQuote = false;
    await tester.tap(find.text('Retry price'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send booking request'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the ticket retries and labels a pending booking hold accurately',
      (tester) async {
    final api = UiApi()..failTicket = true;
    await render(
        tester,
        Scaffold(
            body: BookingTicket(
                rental: sampleRental('PENDING_ADMIN_APPROVAL'), api: api)),
        dark: true);
    await tester.pumpAndSettle();
    expect(find.text('Ticket unavailable'), findsOneWidget);
    api.failTicket = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('R-123456'), findsOneWidget);
    expect(find.textContaining('Review hold ends'), findsOneWidget);
    expect(find.textContaining('Pickup before'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'missing historical due dates do not display an invented overdue timer',
      (tester) async {
    final rental = sampleRental('ACTIVE')
        .copyWith(dueDate: DateTime.fromMillisecondsSinceEpoch(0));
    await render(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: RentalBookingCard(rental: rental))));
    await tester.pumpAndSettle();
    expect(find.text('Return time not recorded'), findsOneWidget);
    expect(find.textContaining('Overdue by'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'notification inbox fits large text and opens the exact rejected booking',
      (tester) async {
    final api = UiApi();
    final inbox = RentalNotificationService(api: api, pushEnabled: false);
    final capture = GlobalKey();
    inbox.setSession('c1');
    await render(
        tester,
        ChangeNotifierProvider.value(
            value: inbox, child: const NotificationsScreen()),
        dark: true,
        width: 390,
        scale: 1,
        capture: capture);
    await tester.pumpAndSettle();
    expect(inbox.unreadCount, 2);
    await save(tester, capture, 'android-notifications');
    await render(
        tester,
        ChangeNotifierProvider.value(
            value: inbox, child: const NotificationsScreen()),
        dark: true,
        capture: capture);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Mark shown as read'));
    await tester.pumpAndSettle();
    expect(inbox.unreadCount, 0);
    await tester.tap(find.text('Booking rejected'));
    await tester.pumpAndSettle();
    expect(find.text('Booking details'), findsOneWidget);
    expect(find.text('ASRI Hotspring Resort'), findsOneWidget);
    expect(api.requests.where((row) => row['rental_id'] == 'r-rejected').length,
        1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    inbox.dispose();
  });
  test('changing codes invalidates verification and ignores an older response',
      () async {
    final pending = Completer<Map<String, dynamic>>();
    final verification =
        ReleaseVerification(rentalId: 'r1', request: (_) => pending.future);
    verification.updateTransaction('old');
    final request = verification.verify();
    verification.updateTransaction('new');
    pending.complete({
      'rental': {'id': 'r1'},
      'booking_verified': true
    });
    await request;
    expect(verification.bookingVerified, isFalse);
    expect(verification.step, 0);
    expect(() => verification.releaseCodes, throwsStateError);
    verification.dispose();
  });
}
