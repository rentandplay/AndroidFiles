import 'package:rent_and_play_app/services/thermal_receipt.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rent_and_play_app/services/server_clock.dart';
import 'package:rent_and_play_app/services/business_settings.dart';
import 'package:rent_and_play_app/services/payment_proof_image.dart';
import 'package:rent_and_play_app/screens/user/checkout_screen.dart';
import 'package:rent_and_play_app/screens/shared/terms_dialog.dart';
import 'package:rent_and_play_app/widgets/live_business_settings.dart';
import 'rental_ui_test.dart' show UiApi, item;
import 'widget_test.dart' show SignedOutAuth;

class _SyncApi extends UiApi {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  bool cash = false, qr = false;
  String announcement = 'Live owner notice';
  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => events.stream;
  @override
  Future<Map<String, dynamic>> paymentInstructions() async => {
        'accept_cash': cash,
        if (qr) 'instapay_qr_data_url': 'https://example.test/qr.png',
      };
  @override
  Future<Map<String, dynamic>> businessSettings() async => {
        'settings': {
          'announcement_enabled': true,
          'announcement_text': announcement,
          'opens_at': '00:00',
          'closes_at': '00:00',
        }
      };
  @override
  Future<Map<String, dynamic>> terms() async => {
        'terms_and_conditions': 'Owner terms',
        'rental_terms': 'Owner rental agreement',
        'privacy_policy': 'Owner privacy policy',
        'refund_policy': 'Owner cancellation policy',
        'terms_version': 'owner-v2',
        'rental_terms_version': 'owner-v2',
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });
  test('thermal receipt uses the saved owner layout', () {
    final lines = thermalReceiptLines({'rental_code': 'R-0001'}, receiptSettings: {
      'receipt_header_title': 'OWNER STORE', 'receipt_branch_line': 'Branch Two',
      'receipt_city_line': 'Owner City', 'receipt_contact_line': 'Contact: 123', 'receipt_footer_note': 'Owner return policy',
    });
    expect(lines.map((line) => line['text']), containsAll(['OWNER STORE', 'Branch Two', 'Owner City', 'Contact: 123', 'Owner return policy']));
  });
  test('server countdown uses elapsed time after device clock changes', () {
    var elapsed = Duration.zero;
    var device = DateTime.utc(2040);
    final clock = ServerClock(elapsed: () => elapsed, localNow: () => device);
    final server = DateTime.utc(2026, 11, 7, 2);
    clock.synchronize(server);
    device = DateTime.utc(2000);
    elapsed = const Duration(minutes: 5);
    expect(clock.now, server.add(const Duration(minutes: 5)));
    device = DateTime.utc(2099);
    elapsed += const Duration(seconds: 10);
    expect(clock.now, server.add(const Duration(minutes: 5, seconds: 10)));
  });
  test('store hours support overnight intervals and exclusive closing time',
      () {
    const hours = {'opens_at': '20:00', 'closes_at': '02:00'};
    expect(withinStoreHours(DateTime.utc(2026, 11, 7, 17), hours), isTrue);
    expect(withinStoreHours(DateTime.utc(2026, 11, 7, 18), hours), isFalse);
    expect(withinStoreHours(DateTime.utc(2026, 11, 7, 12), hours), isTrue);
    expect(formatBusinessTime('20:05'), '8:05 PM');
  });
  test('proof preprocessing produces a bounded JPEG and rejects invalid data',
      () {
    final input = img.encodePng(img.Image(width: 2200, height: 1800));
    final output = compressPaymentProof(input);
    expect(output.length, lessThanOrEqualTo(300000));
    expect(output.take(3), [255, 216, 255]);
    expect(img.decodeJpg(output)!.width, lessThanOrEqualTo(1600));
  });
  testWidgets('checkout hides cash and blocks checkout when QR is unconfigured',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _SyncApi();
    addTearDown(api.events.close);
    await tester
        .pumpWidget(MaterialApp(home: CheckoutScreen(item: item, api: api)));
    await tester.pump();
    final segments = tester
        .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(segments.segments.map((segment) => segment.value), ['QR']);
    expect(segments.selected, {'QR'});
    expect(
        find.text(
            'Electronic checkout is temporarily disabled. Please contact counter staff.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send rental request'))
            .onPressed,
        isNull);
    expect(find.text('Live owner notice'), findsOneWidget);
    api.cash = true;
    api.announcement = 'Updated owner notice';
    api.events.add({'event': 'settings.changed'});
    await tester.pump();
    await tester.pump();
    expect(
        tester
            .widget<SegmentedButton<String>>(
                find.byType(SegmentedButton<String>))
            .segments
            .map((segment) => segment.value),
        ['CASH', 'QR']);
    expect(find.text('Updated owner notice'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('legal section selector shows the saved owner policies',
      (tester) async {
    final api = _SyncApi();
    addTearDown(api.events.close);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TermsDialog(api: api, readOnly: true))));
    await tester.pump();
    expect(find.text('Owner terms'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy Policy (DPA 2012)').last);
    await tester.pumpAndSettle();
    expect(find.text('Owner privacy policy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('announcement is hidden unless both enabled and nonempty',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: LiveAnnouncementBanner(settings: {
      'announcement_enabled': false,
      'announcement_text': 'Hidden'
    })));
    expect(find.text('Hidden'), findsNothing);
  });
}
