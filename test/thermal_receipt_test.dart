import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/services/thermal_receipt.dart';
import 'package:rent_and_play_app/screens/shared/rental_receipt_dialog.dart';
import 'package:rent_and_play_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final snapshot =
      jsonDecode(File('test/fixtures/thermal-receipt.json').readAsStringSync())
          as Map;
  final rental = Map<String, dynamic>.from(snapshot['rental']);
  const channel = MethodChannel('rent_and_play/mx10_printer');
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI_PREVIEWS')) return;
    final sdkRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
    for (final font in {
      'Roboto':
          '$sdkRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      'MaterialIcons':
          '$sdkRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      'monospace': 'C:/Windows/Fonts/consola.ttf',
    }.entries) {
      final file = File(font.value);
      if (await file.exists()) {
        await (FontLoader(font.key)
              ..addFont(file
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes))))
            .load();
      }
    }
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
      'Android and web receipt fields, payment snapshot, public ID and Manila dates match the shared fixture',
      () {
    final lines = thermalReceiptLines(rental);
    expect(
        lines.map((line) => line['text']).toList(), snapshot['expected_text']);
    expect(jsonEncode(lines), isNot(contains('private-qr-token')));
    expect(jsonEncode(lines), isNot(contains('rental_internal')));
    expect(() => thermalReceiptLines({}), throwsStateError);
    final missing = thermalReceiptLines({...rental, 'rental_paid_amount': null})
        .map((line) => line['text']);
    expect(missing, contains('Payment received: Not recorded'));
    expect(missing, contains('Balance due: PHP 0.00'));
  });
  testWidgets(
      'a saved QR printer connection is reused and duplicate receipt submissions remain disabled while printing',
      (tester) async {
    final calls = <MethodCall>[];
    final printed = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getPrinterStatus') {
        return {
          'connected': true,
          'name': 'MX10',
          'printing': false,
          'progress': 0
        };
      }
      if (call.method == 'printRentalReceipt') {
        await printed.future;
        return null;
      }
      return null;
    });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RentalReceiptDialog(rental: rental))));
    await tester.pump();
    expect(find.text('Printer connected'), findsOneWidget);
    expect(find.text('Continuous paper roll'), findsOneWidget);
    final print = find.widgetWithText(FilledButton, 'Print via Bluetooth');
    await tester.ensureVisible(print);
    await tester.tap(print);
    await tester.pump();
    expect((tester.widget<FilledButton>(print)).onPressed, isNull);
    expect(calls.where((call) => call.method == 'discoverPrinters'), isEmpty);
    final payload = calls
        .singleWhere((call) => call.method == 'printRentalReceipt')
        .arguments as Map;
    expect(payload['paperMode'], 'continuous');
    expect((payload['lines'] as List).map((line) => line['text']).toList(),
        snapshot['expected_text']);
    printed.complete();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Receipt sent to printer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'connection and print errors remain recoverable on a narrow receipt dialog',
      (tester) async {
    var connected = false, failPrint = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPrinterStatus') {
        return {'connected': connected, 'name': 'MX10', 'printing': false};
      }
      if (call.method == 'discoverPrinters') {
        return [
          {'id': 'printer', 'name': 'MX10'}
        ];
      }
      if (call.method == 'connectPrinter') {
        connected = true;
        return {'name': 'MX10'};
      }
      if (call.method == 'printRentalReceipt' && failPrint) {
        throw PlatformException(
            code: 'print_failed', message: 'The printer is out of paper.');
      }
      return null;
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RentalReceiptDialog(rental: rental))));
    await tester.pump();
    final print = find.widgetWithText(FilledButton, 'Print via Bluetooth');
    expect(tester.widget<FilledButton>(print).onPressed, isNull);
    expect(tester.getBottomRight(print).dy, lessThan(844));
    await tester.tap(find.text('Connect printer'));
    await tester.pump();
    await tester.pump();
    await tester.tap(print);
    await tester.pump();
    await tester.pump();
    expect(
        find.textContaining('Check any partial paper output'), findsOneWidget);
    expect(tester.widget<FilledButton>(print).onPressed, isNotNull);
    failPrint = false;
    await tester.tap(print);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Receipt sent to printer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'printer status failure can be retried with print controls visible on a small screen',
      (tester) async {
    var statusFails = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPrinterStatus') {
        if (statusFails) {
          throw PlatformException(
              code: 'status_failed', message: 'Connection unavailable');
        }
        return {'connected': true, 'name': 'MX10', 'printing': false};
      }
      return null;
    });
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previewKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!),
          home: Scaffold(
              body: RentalReceiptDialog(rental: {
            ...rental,
            'item_name': 'Bicycle with helmet and accessories'
          })),
        )));
    await tester.pump();
    final print = find.widgetWithText(FilledButton, 'Print via Bluetooth');
    expect(tester.widget<FilledButton>(print).onPressed, isNull);
    expect(tester.getBottomRight(print).dy, lessThan(640));
    expect(find.text('Connection check unavailable'), findsOneWidget);
    statusFails = false;
    await tester.ensureVisible(find.text('Retry connection check'));
    await tester.tap(find.text('Retry connection check'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Printer connected'), findsOneWidget);
    expect(tester.widget<FilledButton>(print).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_UI_PREVIEWS')) {
      tester.view.physicalSize = const Size(390, 844);
      await tester.ensureVisible(find.text('Bluetooth printer'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final boundary = previewKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/ui-preview/receipt-55mm-mobile.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
