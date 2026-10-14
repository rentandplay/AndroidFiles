import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/services/admin_api_service.dart';
import 'package:rent_and_play_app/screens/admin/maintenance_screen.dart';
import 'package:rent_and_play_app/screens/admin/equipment_list_screen.dart';
import 'package:rent_and_play_app/theme/app_theme.dart';
import 'widget_test.dart' show SignedOutAuth;

class _Api extends AdminFirestoreService {
  final calls = <Map<String, dynamic>>[];
  final reads = <String>[];
  bool stale = false;
  bool failStaffOnce = false;
  final ticket = <String, dynamic>{
    'id': 'ticket',
    'maintenance_code': 'M-0001',
    'item_id': 'unit',
    'item_name': 'Bicycle',
    'item_code': 'EQUIP-001',
    'reason': 'Brake cable worn',
    'status': 'IN_PROGRESS',
    'workflow_stage': 'AWAITING_INSPECTION',
    'revision': 7,
    'priority': 'HIGH',
    'repair_cost': null,
    'photos': <Map<String, dynamic>>[],
    'activity': [
      {
        'kind': 'REPAIR',
        'actor_name': 'Operator',
        'note': 'Cable replaced',
        'at': '2026-10-14T02:00:00Z'
      }
    ],
  };
  @override
  Future<Map<String, dynamic>> getMap(String path,
      {bool forceRefresh = false}) async {
    reads.add(path);
    if(path.startsWith('/records/maintenance'))return {'records':[ticket],'nextCursor':null};
    if (path == '/maintenance-staff') {
      if (failStaffOnce) {
        failStaffOnce = false;
        throw const AdminApiException('Staff list unavailable. Retry loading.');
      }
      return {
        'staff': [
          {'id': 'staff', 'full_name': 'Operator'}
        ]
      };
    }
    if (path == '/mobile/admin-workspace') {
      return {
        'maintenance': [ticket],
        'items': [
          {
            'id': 'spare',
            'name': 'Bicycle',
            'item_code': 'EQUIP-002',
            'status': 'AVAILABLE',
            'is_active': true
          },
          {
            'id': 'unit',
            'name': 'Bicycle',
            'item_code': 'EQUIP-001',
            'status': 'UNDER_MAINTENANCE',
            'is_active': true
          },
          {
            'id': 'rented',
            'name': 'Bicycle',
            'item_code': 'EQUIP-003',
            'status': 'RENTED',
            'is_active': true
          },
        ]
      };
    }
    if (path == '/inventory/spare') {
      return {
        'item': {
          'id': 'spare',
          'item_code': 'EQUIP-002',
          'status': 'AVAILABLE',
          'updated_at': 'saved-version'
        }
      };
    }
    return {
      'maintenance': ticket,
      'item': {'id': 'unit', 'status': 'UNDER_MAINTENANCE'}
    };
  }

  @override
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic> body = const {}}) async {
    calls.add({'path': path, ...body});
    return {};
  }

  @override
  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic> body = const {}}) async {
    if (stale) {
      throw const AdminApiException(
          'This ticket changed. Refresh before retrying.',
          statusCode: 409);
    }
    calls.add({'path': path, ...body});
    return {};
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
      'equipment refresh replaces the route snapshot with current unit availability',
      (tester) async {
    var reads = 0;
    final item = {
      'id': 'spare',
      'name': 'Bicycle',
      'item_code': 'EQUIP-002',
      'status': 'AVAILABLE',
      'category': 'Sports'
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EquipmentListScreen(
      items: [item],
      onRefresh: () async {},
      loadItems: () async {
        reads++;
        return [
          {...item, 'status': 'UNDER_MAINTENANCE'}
        ];
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Available'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('Under Maintenance'), findsOneWidget);
    expect(find.text('Available'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'mobile issue report selects one eligible physical unit and sends its saved version',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(
        MaterialApp(home: MaintenanceEditScreen(api: api, unitId: 'spare')));
    await tester.pumpAndSettle();
    expect(find.text('EQUIP-002 · Bicycle'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Issue summary'), 'Pedal loose');
    await tester.tap(find.widgetWithText(FilledButton, 'Report issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(api.calls.single['itemId'], 'spare');
    expect(api.calls.single['version'], 'saved-version');
    expect(api.calls.single['reason'], 'Pedal loose');
    expect(api.calls.single['path'], '/maintenance');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'mobile final inspection requires every check and preserves ticket revision and explicit zero cost',
      (tester) async {
    final api = _Api();
    await tester.pumpWidget(MaterialApp(
        home: MaintenanceEditScreen(
            api: api, ticket: api.ticket, action: 'complete')));
    await tester.pumpAndSettle();
    expect(api.reads, isEmpty,
        reason: 'repair actions do not depend on the staff assignment list');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Work / inspection notes'),
        'Test ride and safety check passed');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Total repair cost (PHP)'), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Complete inspection'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.text('Function, safety and completeness must all pass.'),
        findsOneWidget);
    for (final label in [
      'Function tested and working',
      'Safe to rent',
      'Required parts and accessories complete'
    ]) {
      final check = find.widgetWithText(CheckboxListTile, label);
      await Scrollable.ensureVisible(tester.element(check), alignment: .2);
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Complete inspection'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(api.calls.single['path'], '/maintenance/ticket');
    expect(api.calls.single['revision'], 7);
    expect(api.calls.single['repairCost'], 0);
    expect(api.calls.single['checks'],
        {'functional': true, 'safe': true, 'complete': true});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('maintenance metadata failures block saving and can be retried',
      (tester) async {
    final api = _Api()..failStaffOnce = true;
    await tester.pumpWidget(MaterialApp(
        home: MaintenanceEditScreen(
            api: api, ticket: api.ticket, action: 'update')));
    await tester.pumpAndSettle();
    expect(find.text('Staff list unavailable. Retry loading.'), findsOneWidget);
    final saveButton = find.widgetWithText(FilledButton, 'Update maintenance');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await tester.tap(find.text('Retry loading'));
    await tester.pumpAndSettle();
    expect(api.reads.where((path) => path == '/maintenance-staff').length, 2);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(api.calls.single['path'], '/maintenance/ticket');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'stale repairs require refresh and closed tickets have no repair or release actions',
      (tester) async {
    final api = _Api()..stale = true;
    await tester.pumpWidget(MaterialApp(
        home: MaintenanceEditScreen(
            api: api, ticket: api.ticket, action: 'update')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update maintenance'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('This ticket changed. Refresh before retrying.'),
        findsOneWidget);
    expect(api.calls, isEmpty);
    api.ticket['status'] = 'COMPLETED';
    await tester.pumpWidget(
        MaterialApp(home: MaintenanceTicketScreen(id: 'ticket', api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Update cost / notes'), findsOneWidget);
    expect(find.text('Complete inspection'), findsNothing);
    expect(find.text('Start repair'), findsNothing);
    expect(find.text('Retire this unit'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'maintenance list fits phone width and photos are encoded within backend limits',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.runAsync(() async {
      final sdkRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
      final font = File(
          '$sdkRoot/bin/cache/artifacts/material_fonts/roboto-regular.ttf');
      if (await font.exists()) {
        final loader = FontLoader('Roboto')
          ..addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
      final icons = File(
          '$sdkRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
      if (await icons.exists()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(
              icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: MaintenanceScreen(api: _Api()))));
    await tester.pumpAndSettle();
    expect(find.textContaining('M-0001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final capture = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/android-maintenance.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      capture.dispose();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.orange);
      final picture = recorder.endRecording();
      final image = await picture.toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      final encoded = await encodeMaintenancePhoto(data!.buffer.asUint8List());
      expect(encoded.length, lessThanOrEqualTo(200000));
      expect(base64Decode(encoded.split(',').last).take(8),
          [137, 80, 78, 71, 13, 10, 26, 10]);
      await expectLater(encodeMaintenancePhoto(Uint8List(10 * 1024 * 1024 + 1)),
          throwsFormatException);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
