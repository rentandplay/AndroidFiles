import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:rent_and_play_app/models/rental_model.dart';
import 'package:rent_and_play_app/screens/admin/rental_admin_view.dart';
import 'package:rent_and_play_app/screens/shared/qr_capture_screen.dart';
import 'package:rent_and_play_app/screens/shared/transaction_ticket_dialog.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/services/rental_offline_cache.dart';
import 'widget_test.dart' show SignedOutAuth;

const _onePixelPngDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0ioAAAAASUVORK5CYII=';

class _OfflineTicketApi extends MobileApiService {
  bool offline = false;

  @override
  Future<Map<String, dynamic>> rentalTicket(String id) async {
    if (offline) {
      throw const MobileApiException(
          'Unable to connect to the server. Please check your internet connection and try again.');
    }
    return {
      'status': 'APPROVED',
      'delivery_status': 'OUT_FOR_DELIVERY',
      'rental_code': 'R-7788',
      'rolling_pin': '654321',
      'image_data_url': _onePixelPngDataUrl,
      'hold_expires_at':
          DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
    };
  }
}

class _TorchTestCameraPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  final torchChanges = StreamController<TorchState>.broadcast();
  TorchState currentTorch = TorchState.off;
  bool denied = false;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => torchChanges.stream;

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (denied) {
      throw const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied);
    }
    return MobileScannerViewAttributes(
      currentTorchMode: currentTorch,
      numberOfCameras: 2,
      size: const Size(480, 640),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> toggleTorch() async {
    currentTorch =
        currentTorch == TorchState.on ? TorchState.off : TorchState.on;
    torchChanges.add(currentTorch);
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> dispose() async {}
}

RentalModel _sampleApprovedRental({String customerId = 'cust-villa-4'}) =>
    RentalModel(
      rentalId: 'rent-villa-4',
      itemId: 'item-karaoke',
      itemName: 'Portable Karaoke Set',
      customerId: customerId,
      customerName: 'Maria Clara',
      terminalId: 'TERM-01',
      deliveryLocation: 'Villa 4 · Lakewood Subdivision',
      startDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(hours: 6)),
      rateFee: 650,
      latePenalty: 0,
      paymentMethod: 'QR',
      paymentConfirmedByAdmin: true,
      status: 'APPROVED',
      returnCondition: 'Good',
      conditionNotes: '',
      rentalCode: 'R-7788',
      deliveryStatus: 'OUT_FOR_DELIVERY',
      fulfillmentMode: 'DELIVERY',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
      'RentalOfflineCache scopes saved rentals and tickets per customer account and strips rolling PINs',
      () async {
    final rental = _sampleApprovedRental(customerId: 'cust-a');
    await RentalOfflineCache.saveRentals('cust-a', [rental]);
    await RentalOfflineCache.saveTicket('cust-a', rental.rentalId, {
      'status': 'APPROVED',
      'rental_code': 'R-7788',
      'rolling_pin': '123456',
      'image_data_url': _onePixelPngDataUrl,
    });

    final loadedA = await RentalOfflineCache.loadRentals('cust-a');
    expect(loadedA, isNotNull);
    expect(loadedA!.rentals.single.itemName, 'Portable Karaoke Set');
    expect(loadedA.rentals.single.rentalCode, 'R-7788');

    final ticketA =
        await RentalOfflineCache.loadTicket('cust-a', rental.rentalId);
    expect(ticketA, isNotNull);
    expect(ticketA!['offline_cached'], isTrue);
    expect(ticketA['rental_code'], 'R-7788');
    expect(ticketA.containsKey('rolling_pin'), isFalse);

    // Another account must never see cust-a's cached records or QR ticket.
    expect(await RentalOfflineCache.loadRentals('cust-b'), isNull);
    expect(
        await RentalOfflineCache.loadTicket('cust-b', rental.rentalId), isNull);
  });

  testWidgets(
      'EmbeddedRentalHandoffQr caches live QR pass and falls back cleanly when resort signal drops',
      (tester) async {
    final api = _OfflineTicketApi();
    final rental = _sampleApprovedRental();

    // 1. Online load caches the ticket and displays live rolling PIN.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmbeddedRentalHandoffQr(rental: rental, api: api),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('LIVE HANDOVER QR & PIN'), findsOneWidget);
    expect(find.text('654321'), findsOneWidget);
    expect(find.text('Rental code: R-7788'), findsOneWidget);

    // 2. Resort dead-spot: re-mounting offline shows saved QR pass without stale rolling PIN.
    api.offline = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmbeddedRentalHandoffQr(rental: rental, api: api),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('SAVED OFFLINE HANDOVER QR'), findsOneWidget);
    expect(find.text('Rental code: R-7788'), findsOneWidget);
    expect(find.text('654321'), findsNothing);
    expect(find.text('Retry live'), findsOneWidget);

    // 3. Reconnecting restores live rolling PIN.
    api.offline = false;
    await tester.tap(find.text('Retry live'));
    await tester.pumpAndSettle();
    expect(find.text('LIVE HANDOVER QR & PIN'), findsOneWidget);
    expect(find.text('654321'), findsOneWidget);
  });

  testWidgets(
      'PaymentProofPreview opens full-screen zoomable InteractiveViewer with transfer reference',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PaymentProofPreview(
          imageDataUrl: _onePixelPngDataUrl,
          reference: 'GCASH-998877',
          expectedTotal: '₱650.00',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tap to zoom'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('payment-proof-preview-tap')));
    await tester.pumpAndSettle();

    expect(find.text('Payment receipt preview'), findsOneWidget);
    expect(find.textContaining('Expected ₱650.00'), findsOneWidget);
    expect(find.textContaining('Ref: GCASH-998877'), findsOneWidget);
    expect(find.byKey(const ValueKey('payment-proof-interactive-viewer')),
        findsOneWidget);

    await tester.tap(find.byTooltip('Close preview'));
    await tester.pumpAndSettle();
    expect(find.text('Payment receipt preview'), findsNothing);
  });

  testWidgets(
      'QrCaptureScreen displays one-thumb low-light flashlight pill and updates state on toggle',
      (tester) async {
    final original = MobileScannerPlatform.instance;
    final camera = _TorchTestCameraPlatform();
    MobileScannerPlatform.instance = camera;
    addTearDown(() async {
      await camera.captures.close();
      await camera.torchChanges.close();
      MobileScannerPlatform.instance = original;
    });

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const MaterialApp(
      home: QrCaptureScreen(title: 'Scan resort handoff QR'),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scanner-torch-pill')), findsOneWidget);
    expect(find.text('Low light? Tap for flashlight'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('scanner-torch-pill')));
    await tester.pumpAndSettle();

    expect(find.text('Flashlight on · Tap to turn off'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
