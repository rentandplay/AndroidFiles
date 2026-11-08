import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rent_and_play_app/models/staff_scan.dart';
import 'package:rent_and_play_app/screens/shared/qr_capture_screen.dart';
import 'staff_scanner_test.dart' show CameraPlatform;
import 'package:rent_and_play_app/models/user_model.dart';
import 'package:rent_and_play_app/providers/theme_provider.dart';
import 'package:rent_and_play_app/screens/admin/admin_dashboard_screen.dart';
import 'package:rent_and_play_app/screens/admin/equipment_list_screen.dart';
import 'package:rent_and_play_app/screens/admin/rental_admin_view.dart';
import 'package:rent_and_play_app/screens/profile/profile_screen.dart';
import 'package:rent_and_play_app/services/admin_firestore_service.dart';
import 'package:rent_and_play_app/services/auth_service.dart';
import 'package:rent_and_play_app/theme/app_theme.dart';
import 'package:rent_and_play_app/widgets/staff_ui.dart';
import 'package:rent_and_play_app/widgets/liquid_glass.dart';

import 'widget_test.dart' show SignedOutAuth;

class StaffUser extends Fake implements User {
  @override
  String get uid => 'operator';
  @override
  String get email => 'alex@example.com';
  @override
  String get displayName => 'Alex Santos';
  @override
  String? get photoURL => null;
}

class StaffAuth extends AuthService {
  @override
  User get currentUser => StaffUser();
  @override
  Future<UserModel> getCurrentUserModel() async => UserModel(
      uid: 'operator',
      name: 'Alex Santos',
      email: 'alex@example.com',
      phone: '09123456789',
      role: 'OWNER');
}

final sampleRows = <Map<String, dynamic>>[
  {
    'id': 'late',
    'rental_code': 'R-0015',
    'item_code': 'EQUIP-030',
    'item_name': 'Bingo Set',
    'customer_name': 'Cristina Santos',
    'status': 'ACTIVE',
    'due_at': DateTime.now()
        .subtract(const Duration(hours: 5))
        .toUtc()
        .toIso8601String(),
    'balance_due': 0
  },
  {
    'id': 'new',
    'rental_code': 'R-0023',
    'item_code': 'EQUIP-009',
    'item_name': 'Nintendo Switch',
    'customer_name': 'Jamie Cruz',
    'status': 'PENDING_ADMIN_APPROVAL',
    'payment_method': 'CASH',
    'hold_expires_at': '2026-11-07T12:00:00Z',
    'balance_due': 350
  },
  {
    'id': 'handoff',
    'rental_code': 'R-0024',
    'item_code': 'EQUIP-007',
    'item_name': 'Deck of Cards',
    'customer_name': 'Sam Reyes',
    'status': 'APPROVED',
    'hold_expires_at': '2026-11-07T12:00:00Z',
    'balance_due': 0
  },
  {
    'id': 'inspection',
    'rental_code': 'R-0016',
    'item_code': 'EQUIP-025',
    'item_name': 'Jenga',
    'customer_name': 'Robin Lim',
    'status': 'RETURN_PENDING_INSPECTION',
    'received_at': '2026-11-07T04:00:00Z',
    'balance_due': 0
  },
];

class StaffApi extends AdminFirestoreService {
  @override
  bool get hasSession => true;
  @override
  Map<String, dynamic> get currentUser =>
      {'name': 'Alex Santos', 'role': 'OWNER'};
  @override
  Future<Map<String, dynamic>> restoreAdminSession() async => currentUser;
  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => const Stream.empty();
  @override
  Future<Map<String, dynamic>> loadWorkspace(
          {bool forceRefresh = false}) async =>
      {
        'transactions': sampleRows,
        'items': [],
        '_dashboard': {
          'rentals': sampleRows,
          'stats': {'available': 44}
        },
      };
  @override
  Future<Map<String, dynamic>> getMap(String path,
          {bool forceRefresh = false}) async =>
      {
        'counter': {'due_today': 2},
        'totals': {'cash_collections': 1250, 'qr_collections': 850},
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  late MobileScannerPlatform originalCamera;
  late CameraPlatform camera;
  setUp(() {
    originalCamera = MobileScannerPlatform.instance;
    camera = CameraPlatform();
    MobileScannerPlatform.instance = camera;
    StaffScanSession.lastMode = StaffScanMode.rental;
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = originalCamera;
  });
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
    final root = 'C:/flutter/bin/cache/artifacts/material_fonts';
    if (Directory(root).existsSync()) {
      final font = FontLoader('Roboto');
      for (final name in [
        'roboto-regular.ttf',
        'roboto-medium.ttf',
        'roboto-bold.ttf'
      ]) {
        font.addFont(Future.value(
            ByteData.sublistView(await File('$root/$name').readAsBytes())));
      }
      await font.load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(
                await File('$root/materialicons-regular.otf').readAsBytes()))))
          .load();
    }
  });

  Future<GlobalKey> render(WidgetTester tester, Widget page,
      {double width = 390, double scale = 1, bool dark = false}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = StaffAuth();
    final appearance = ThemeProvider();
    if (dark) appearance.toggleTheme(true);
    addTearDown(auth.dispose);
    addTearDown(appearance.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: appearance)
      ],
      child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme:
                StaffTheme.from(dark ? AppTheme.darkTheme : AppTheme.lightTheme)
                    .copyWith(
                        textTheme: StaffTheme.from(
                                dark ? AppTheme.darkTheme : AppTheme.lightTheme)
                            .textTheme
                            .apply(fontFamily: 'Roboto')),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: LiquidGlassScope(
                    child: LiquidAmbientBackdrop(child: child!))),
            home: page,
          )),
    ));
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
      'counter opens the camera immediately and keeps the queue when cancelled',
      (tester) async {
    final key = await render(
        tester, AdminDashboardScreen(api: StaffApi(), onSignedOut: () {}));
    expect(tester.takeException(), isNull);
    await save(tester, key, 'admin-counter');
    await tester.tap(find.text('1 overdue rental'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Overdue'))
            .selected,
        isTrue);
    expect(find.text('Bingo Set'), findsOneWidget);
    expect(find.text('Nintendo Switch'), findsNothing);
    await save(tester, key, 'admin-returns');
    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle();
    expect(find.byType(QrCaptureScreen), findsOneWidget);
    expect(find.text('Scan a code'), findsNothing);
    expect(find.text('Rental QR'), findsOneWidget);
    expect(find.text('Equipment QR'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('scan-mode-equipment')));
    await tester.pumpAndSettle();
    await save(tester, key, 'admin-scan');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Return queue'), findsOneWidget);
    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle();
    expect(find.text(StaffScanMode.equipment.instruction), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'rental search, filters and workflow guide remain usable at large text',
      (tester) async {
    await render(
        tester,
        Scaffold(
            body: RentalAdminView(
                page: 'Rentals',
                workspace: {'transactions': sampleRows},
                onChanged: () async {})),
        width: 320,
        scale: 1.6);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'Bingo');
    await tester.pumpAndSettle();
    expect(find.text('Nintendo Switch'), findsNothing);
    await tester.ensureVisible(find.text('Receive equipment'));
    expect(find.text('Bingo Set'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Workflow guide'));
    await tester.tap(find.byTooltip('Workflow guide'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Clear search'));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Nintendo Switch'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'account settings are discoverable and contact fields fit a narrow phone',
      (tester) async {
    final key = await render(tester, const ProfileScreen(showAppBar: false),
        width: 390);
    await save(tester, key, 'admin-account');
    expect(find.text('Business details'), findsOneWidget);
    expect(find.text('Your profile'), findsOneWidget);
    await tester.tap(find.text('Your profile'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 844);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Full Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Phone Number'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Your profile'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'equipment category controls grow with large text and still filter',
      (tester) async {
    await render(
        tester,
        Scaffold(
            body: EquipmentListScreen(items: const [
          {
            'name': 'Nintendo Switch',
            'item_code': 'EQUIP-009',
            'category': 'Gaming',
            'status': 'AVAILABLE'
          },
          {
            'name': 'Bingo Set',
            'item_code': 'EQUIP-030',
            'category': 'Board Games',
            'status': 'RENTED'
          },
        ], onRefresh: () async {})),
        width: 320,
        scale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Gaming'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Gaming'));
    await tester.pumpAndSettle();
    expect(find.text('Nintendo Switch'), findsOneWidget);
    expect(find.text('Bingo Set'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'counter, camera modes and account fit 320dp with 200 percent text',
      (tester) async {
    await render(
        tester, AdminDashboardScreen(api: StaffApi(), onSignedOut: () {}),
        width: 320, scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Appearance'));
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dark rental queue and tablet counter retain the same hierarchy',
      (tester) async {
    final key = await render(
        tester,
        Scaffold(
            appBar: AppBar(title: const Text('Rentals')),
            body: RentalAdminView(
                page: 'Rentals',
                workspace: {'transactions': sampleRows},
                onChanged: () async {})),
        dark: true);
    await save(tester, key, 'admin-rentals-dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await render(
        tester, AdminDashboardScreen(api: StaffApi(), onSignedOut: () {}),
        width: 1024);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
