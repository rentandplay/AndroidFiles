import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rent_and_play_app/screens/shared/qr_capture_screen.dart';
import 'package:rent_and_play_app/services/admin_firestore_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'local_connection_test.dart' as connection;

// Hardware and live read-only checks. No accounts, rentals or payments are created.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  connection.main();
  testWidgets(
      'phone scanner decodes equipment and rental QR images with the native decoder',
      (tester) async {
    final controller = MobileScannerController(
        autoStart: false, formats: const [BarcodeFormat.qrCode]);
    try {
      for (final value in [
        'rp-qr-device-equipment-fixture',
        'rp-rental-device-handoff-fixture'
      ]) {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        canvas.drawRect(
            const Rect.fromLTWH(0, 0, 384, 384), Paint()..color = Colors.white);
        canvas.translate(32, 32);
        QrPainter(data: value, version: QrVersions.auto, gapless: true)
            .paint(canvas, const Size(320, 320));
        final picture = recorder.endRecording(),
            image = await picture.toImage(384, 384);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file =
            File('${Directory.systemTemp.path}/rent-play-scanner-fixture.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        try {
          final capture = await controller
              .analyzeImage(file.path)
              .timeout(const Duration(seconds: 20));
          expect(capture?.barcodes.map((barcode) => barcode.rawValue),
              contains(value));
          debugPrint('Device scanner: native QR image decode passed.');
        } finally {
          await file.delete();
          image.dispose();
          picture.dispose();
        }
      }
    } finally {
      await controller.dispose();
    }
  });
  testWidgets(
      'physical phone camera captures one exact QR through the actual staff scanner screen',
      (tester) async {
    const expected = 'rp-optical-device-check-20261014';
    final scanned = Completer<String?>();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: Center(
                        child: FilledButton(
                  onPressed: () async {
                    final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const QrCaptureScreen(
                                title: 'Scanner verification')));
                    scanned.complete(result);
                  },
                  child: const Text('Test camera scanner'),
                ))))));
    await tester.tap(find.text('Test camera scanner'));
    for (var attempt = 0; attempt < 300 && !scanned.isCompleted; attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
      final scanners = find.byType(MobileScanner);
      if (scanners.evaluate().isNotEmpty &&
          tester.widget<MobileScanner>(scanners).controller!.value.isRunning) {
        break;
      }
    }
    if (!scanned.isCompleted) {
      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      expect(scanner.controller!.value.error, isNull,
          reason:
              'Allow camera access for Rent and Play before this hardware test.');
      expect(scanner.controller!.value.isRunning, true);
      debugPrint(
          'Device scanner: camera running; point the phone at the optical test QR.');
    }
    final result = await tester
        .runAsync(() => scanned.future.timeout(const Duration(seconds: 90)));
    expect(result, expected);
    await tester.pumpAndSettle();
    expect(find.byType(QrCaptureScreen), findsNothing);
    debugPrint(
        'Device scanner: actual camera scan returned the exact fixture value once.');
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets(
      'the existing signed-in staff account can restore and read its live mobile workspace',
      (tester) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      markTestSkipped(
          'Sign in as Owner or Operator on the normal app before running this read-only staff session check.');
      return;
    }
    final profile = (await MobileApiService.instance.profile())['user'] as Map;
    if (!['OWNER', 'OPERATOR'].contains(profile['role'])) {
      markTestSkipped(
          'The phone has a customer session; staff credentials must be entered by the user.');
      return;
    }
    final api = AdminFirestoreService.instance;
    expect((await api.restoreAdminSession())['role'], profile['role']);
    final workspace = await api.loadWorkspace();
    expect(workspace['transactions'], isA<List>());
    expect(workspace['_dashboard'], isA<Map>());
    debugPrint(
        'Device scanner: existing ${profile['role']} session restored and staff workspace read successfully.');
  });
}
