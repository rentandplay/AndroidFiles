import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';
import 'package:rent_and_play_app/screens/shared/qr_capture_screen.dart';
import 'package:rent_and_play_app/screens/admin/rental_admin_view.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'widget_test.dart' show SignedOutAuth;

class CameraPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  bool denied = false, failStop = false, failTorch = false;
  int starts = 0, stops = 0;
  Completer<void>? delayedStop;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (denied) {
      throw const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied);
    }
    return const MobileScannerViewAttributes(
        currentTorchMode: TorchState.off,
        numberOfCameras: 2,
        size: Size(480, 640));
  }

  @override
  Future<void> stop() async {
    stops++;
    if (delayedStop != null) await delayedStop!.future;
    if (failStop) throw PlatformException(code: 'camera_stop_failed');
  }

  @override
  Future<void> toggleTorch() async {
    if (failTorch) throw PlatformException(code: 'torch_failed');
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {}
  void scan(String code) => captures.add(BarcodeCapture(
      barcodes: [Barcode(rawValue: code, format: BarcodeFormat.qrCode)]));
}

class ScanApi extends MobileApiService {
  ScanApi(this.row);
  final Map<String, dynamic> row;
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> adminRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      bool forceRefresh = false}) async {
    calls.add({'path': path, ...?body});
    return {'rental': row, 'rental_verified': true, 'delivery_prepared': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  late CameraPlatform camera;
  late MobileScannerPlatform original;
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = CameraPlatform();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = original;
  });
  Future<void> open(WidgetTester tester,
      {void Function(String?)? onResult}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      final result = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const QrCaptureScreen(
                                  title: 'Scan rental QR')));
                      onResult?.call(result);
                    },
                    child: const Text('Open scanner'))))));
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'camera permission denial is recoverable and controls stay disabled until camera runs',
      (tester) async {
    camera.denied = true;
    await open(tester);
    expect(find.text('Camera access is needed'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Switch camera'))
            .onPressed,
        isNull);
    camera.denied = false;
    await tester.tap(find.text('Retry camera'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access is needed'), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Switch camera'))
            .onPressed,
        isNotNull);
    await close(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'duplicate QR frames return one exact value even when native camera stop fails',
      (tester) async {
    final results = <String?>[];
    await open(tester, onResult: results.add);
    camera.failStop = true;
    camera.scan('  rp-rental-exact-token  ');
    camera.scan('rp-rental-exact-token');
    await tester.pumpAndSettle();
    expect(results, ['rp-rental-exact-token']);
    expect(find.byType(QrCaptureScreen), findsNothing);
    await close(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'QR codes outside the viewfinder window are ignored until placed inside the window',
      (tester) async {
    final results = <String?>[];
    await open(tester, onResult: results.add);
    // Outside the viewfinder window (top left at x=10, y=10)
    camera.captures.add(const BarcodeCapture(
      size: Size(480, 640),
      barcodes: [
        Barcode(
          rawValue: 'outside-code',
          corners: [Offset(10, 10), Offset(30, 10), Offset(30, 30), Offset(10, 30)],
        ),
      ],
    ));
    await tester.pump();
    expect(results, isEmpty);
    expect(find.byType(QrCaptureScreen), findsOneWidget);

    // Inside the viewfinder window (center of 480x640: x=240, y=320)
    camera.captures.add(const BarcodeCapture(
      size: Size(480, 640),
      barcodes: [
        Barcode(
          rawValue: 'inside-code',
          corners: [Offset(230, 310), Offset(250, 310), Offset(250, 330), Offset(230, 330)],
        ),
      ],
    ));
    await tester.pumpAndSettle();
    expect(results, ['inside-code']);
    expect(find.byType(QrCaptureScreen), findsNothing);
    await close(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'pause and resume serialize camera changes and flashlight failures stay recoverable',
      (tester) async {
    await open(tester);
    camera.delayedStop = Completer<void>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(camera.starts, 1);
    camera.delayedStop!.complete();
    await tester.pumpAndSettle();
    expect(camera.starts, 2);
    camera.failTorch = true;
    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not change the camera'), findsOneWidget);
    await close(tester);
    expect(tester.takeException(), isNull);
  });
  for (final scenario in [
    {'kind': 'INVENTORY', 'status': 'APPROVED', 'action': 'prepare-delivery'},
    {'kind': 'BOOKING', 'status': 'APPROVED', 'action': 'release'},
    {'kind': 'INVENTORY', 'status': 'ACTIVE', 'action': 'receipt'},
    {
      'kind': 'INVENTORY',
      'status': 'RETURN_PENDING_INSPECTION',
      'action': 'complete-return'
    },
  ]) {
    final kind = scenario['kind']!;
    testWidgets(
        '$kind staff scan opens ${scenario['action']} for the exact rental',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final row = {
        'id': 'rental-one',
        'status': scenario['status'],
        'rental_code': 'R-0042',
        'item_name': 'Bicycle',
        'item_code': 'EQUIP-017',
        'customer_name': 'Test Customer',
        'rental_fee': 200,
        'delivery_status': kind == 'BOOKING' ? 'PREPARED' : '',
        'fulfillment_mode': 'DELIVERY'
      };
      final api = ScanApi(row);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RentalAdminView(
                  page: 'Rentals',
                  workspace: {
                    'transactions': [row]
                  },
                  onChanged: () async {},
                  initialScanKind: kind,
                  api: api))));
      await tester.pumpAndSettle();
      final code =
          kind == 'INVENTORY' ? 'rp-unit-exact-token' : 'rp-rental-exact-token';
      camera.scan(code);
      await tester.pumpAndSettle();
      final action = tester.widget<RentalAdminActionScreen>(
          find.byType(RentalAdminActionScreen));
      expect(action.action, scenario['action']);
      expect(action.row['id'], 'rental-one');
      expect(action.row['item_code'], 'EQUIP-017');
      expect(action.scannedCode, code);
      expect(api.calls.single['path'], '/rentals/lookup');
      expect(api.calls.single['kind'], kind);
      expect(api.calls.single['code'], code);
      if (kind == 'BOOKING') {
        await tester
            .tap(find.widgetWithText(FilledButton, 'Verify customer rental'));
        await tester.pumpAndSettle();
        expect(api.calls.last['transactionCode'], code);
        expect(find.text('Rental and prepared unit verified'), findsOneWidget);
        expect(
            api.calls
                .where((call) => call['path'].toString().endsWith('/release')),
            isEmpty);
      }
      await close(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
