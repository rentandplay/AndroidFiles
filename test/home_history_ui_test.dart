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
import 'package:rent_and_play_app/models/item_model.dart';
import 'package:rent_and_play_app/models/rental_model.dart';
import 'package:rent_and_play_app/models/user_model.dart';
import 'package:rent_and_play_app/screens/rental/rental_history_screen.dart';
import 'package:rent_and_play_app/screens/user/catalog_screen.dart';
import 'package:rent_and_play_app/screens/user/home_screen.dart';
import 'package:rent_and_play_app/services/auth_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/theme/app_theme.dart';
import 'package:rent_and_play_app/widgets/home_discovery.dart';

import 'widget_test.dart' show SignedOutAuth;

class _Customer extends Fake implements User {
  @override
  String get uid => 'customer';
  @override
  String get displayName => 'Jhon Saberon';
}

class _CustomerAuth extends AuthService {
  @override
  User get currentUser => _Customer();
  @override
  Future<UserModel?> getCurrentUserModel() async => null;
}

class _HomeApi extends MobileApiService {
  bool failCatalog = false;
  int catalogCalls = 0;
  List<Map<String, dynamic>> items =
      ItemModel.getInitialCatalog().map((item) => item.toMap()).toList();
  List<RentalModel> rentals = [];

  @override
  Future<List<Map<String, dynamic>>> catalog() async {
    catalogCalls++;
    if (failCatalog) throw const MobileApiException('Catalog unavailable.');
    return items;
  }

  @override
  Future<List<RentalModel>> listRentals() async => rentals;
}

RentalModel _rental(String id, String name,
        {double due = 0, double refund = 0}) =>
    RentalModel(
      rentalId: id,
      rentalCode: 'R-000$id',
      itemId: id,
      itemName: name,
      customerId: 'customer',
      customerName: 'Jhon Saberon',
      terminalId: '',
      startDate: DateTime.utc(2026, 10, 10, 15, 3),
      dueDate: DateTime.utc(2026, 10, 11, 3, 3),
      returnedDate: DateTime.utc(2026, 10, 11, 3),
      rateFee: 50,
      paymentMethod: 'CASH',
      status: 'COMPLETED',
      paymentStatus: refund > 0
          ? 'REFUND_PENDING'
          : due > 0
              ? 'BALANCE_DUE'
              : 'PAID',
      balanceDue: due,
      refundDue: refund,
    );

const _destinations = [
  NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
  NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Browse'),
  NavigationDestination(
      icon: Icon(Icons.shopping_bag_outlined), label: 'Rentals'),
  NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
  NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
    final fonts = Directory('C:/flutter/bin/cache/artifacts/material_fonts');
    if (fonts.existsSync()) {
      final roboto = FontLoader('Roboto');
      for (final file in fonts.listSync().whereType<File>().where((file) =>
          file.path.endsWith('.ttf') && file.path.contains('roboto-'))) {
        roboto.addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())));
      }
      await roboto.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(
            await File('${fonts.path}/materialicons-regular.otf')
                .readAsBytes())));
      await icons.load();
    }
  });

  Future<GlobalKey> render(WidgetTester tester, Widget screen,
      {bool dark = false,
      bool history = false,
      double width = 360,
      double scale = 1}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final capture = GlobalKey();
    final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    await tester.pumpWidget(RepaintBoundary(
      key: capture,
      child: ChangeNotifierProvider<AuthService>(
        create: (_) => _CustomerAuth(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: theme.colorScheme.surface,
                surfaceTintColor: Colors.transparent,
                indicatorColor: theme.colorScheme.primary
                    .withValues(alpha: dark ? .2 : .12),
                iconTheme: WidgetStateProperty.resolveWith((states) =>
                    IconThemeData(
                        color: states.contains(WidgetState.selected)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant)),
                labelTextStyle: WidgetStateProperty.resolveWith((states) =>
                    TextStyle(
                        color: states.contains(WidgetState.selected)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: states.contains(WidgetState.selected)
                            ? FontWeight.w700
                            : FontWeight.w500)),
              )),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: screen,
            bottomNavigationBar: NavigationBar(
              height: 72,
              selectedIndex: history ? 3 : 0,
              destinations: _destinations,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final imageContext = tester.element(find.byType(NavigationBar));
    await tester.runAsync(() async {
      for (final image in ItemModel.getInitialCatalog()
          .map((item) => item.cleanImageUrl)
          .toSet()) {
        await precacheImage(AssetImage(image), imageContext);
      }
    });
    await tester.pumpAndSettle();
    return capture;
  }

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI_PREVIEWS')) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Finder getVerticalScroll() => find
      .byWidgetPredicate((widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down)
      .first;

  Future<void> reveal(WidgetTester tester, Finder target) async {
    for (var attempt = 0;
        attempt < 14 && target.hitTestable().evaluate().isEmpty;
        attempt++) {
      await tester.drag(getVerticalScroll(), const Offset(0, -150));
      await tester.pumpAndSettle();
    }
    expect(target.hitTestable(), findsOneWidget);
  }

  testWidgets(
      'Home opens categories and equipment using live prices without repeating featured items',
      (tester) async {
    final api = _HomeApi();
    api.items.firstWhere((item) => item['name'] == 'Bingo Set')['rateOptions'] =
        [
      {'amount': 150, 'label': '5 hours'},
      {'amount': 50, 'label': 'hour'},
    ];
    String? category;
    ItemModel? selected;
    final screen = HomeScreen(
        api: api,
        onBrowse: () {},
        onViewRentals: () {},
        onBrowseCategory: (value) => category = value,
        onItemSelected: (item) => selected = item);
    final capture = await render(tester, screen);
    expect(find.text('No active rentals right now.'), findsOneWidget);
    await save(tester, capture, 'home-light-top');
    await tester.scrollUntilVisible(find.text('Browse by category'), 100,
        scrollable: getVerticalScroll());
    await tester.tap(find.text('Board Games').first);
    expect(category, 'Board Games');
    await tester.scrollUntilVisible(find.text('Bingo Set'), 100,
        scrollable: getVerticalScroll());
    expect(find.text('From ₱50 / hour'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(HomeDiscovery), matching: find.text('Bicycle')),
        findsNothing);
    await Scrollable.ensureVisible(tester.element(find.text('Bingo Set')),
        alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bingo Set'));
    expect(selected?.name, 'Bingo Set');
    final horizontal = find
        .descendant(
            of: find.byType(HomeDiscovery),
            matching: find.byWidgetPredicate((widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.right))
        .last;
    tester.state<ScrollableState>(horizontal).position.jumpTo(0);
    await Scrollable.ensureVisible(
        tester.element(find.text('Browse by category')),
        alignment: .02);
    await tester.pumpAndSettle();
    await save(tester, capture, 'home-light-discovery');
    await reveal(tester, find.text('How it works'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());

    final dark =
        await render(tester, screen, dark: true, width: 320, scale: 1.4);
    await reveal(tester, find.text('How it works'));
    await save(tester, dark, 'home-dark-large-text');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Home handles catalog failure, retry, and unavailable equipment honestly',
      (tester) async {
    final api = _HomeApi()..failCatalog = true;
    String? selected;
    await render(
        tester,
        HomeScreen(
            api: api,
            onBrowse: () {},
            onViewRentals: () {},
            onItemSelected: (item) => selected = item.name));
    await tester.scrollUntilVisible(find.byTooltip('Retry equipment'), 120,
        scrollable: getVerticalScroll());
    expect(find.text('Equipment could not load. Try again.'), findsOneWidget);
    api.failCatalog = false;
    api.items = [
      ItemModel.getInitialCatalog().first.toMap(),
      {
        ...ItemModel.getInitialCatalog()[5].toMap(),
        'status': 'unavailable',
        'available_quantity': 0
      },
    ];
    await tester.tap(find.byTooltip('Retry equipment'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Unavailable'), 100,
        scrollable: getVerticalScroll());
    expect(find.text('Available'), findsNothing);
    await Scrollable.ensureVisible(tester.element(find.text('Deck of Cards')),
        alignment: .3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deck of Cards'));
    expect(selected, 'Deck of Cards');
    expect(api.catalogCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Category shortcuts clear stale Browse search and filters',
      (tester) async {
    final key = GlobalKey<CatalogScreenState>();
    await render(
        tester,
        CatalogScreen(
            key: key, api: _HomeApi(), initialCategory: 'Tech Rentals'));
    await tester.enterText(find.byType(TextField), 'PlayStation');
    await tester.pumpAndSettle();
    key.currentState!.selectCategory('Board Games');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Jenga'), findsOneWidget);
    expect(find.text('PlayStation 4 Console'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'History defaults to compact, opens full details, and keeps search across view changes',
      (tester) async {
    final api = _HomeApi()
      ..rentals = [
        _rental('4', 'Basketball', due: 2250),
        _rental('8', 'Pickleball Set', due: 960, refund: 100),
        _rental('9', 'Jenga'),
      ];
    final capture =
        await render(tester, RentalHistoryScreen(api: api), history: true);
    final toggle = find.byKey(const ValueKey('history-compact-switch'));
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(
        tester.getSize(find.byKey(const ValueKey('history-compact-4'))).height,
        lessThan(165));
    expect(find.text('Due ₱960.00'), findsOneWidget);
    expect(find.text('Refund ₱100.00'), findsOneWidget);
    await save(tester, capture, 'history-compact-light');
    await tester.tap(find.text('Basketball'));
    await tester.pumpAndSettle();
    expect(find.text('Pickup location'), findsOneWidget);
    expect(find.text('Balance due'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pickleball');
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('View details  ›'), findsOneWidget);
    expect(find.text('Basketball'), findsNothing);
    expect(find.text('Due ₱960.00'), findsOneWidget);
    expect(find.text('Refund ₱100.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());

    final dark = await render(tester, RentalHistoryScreen(api: api),
        history: true, dark: true, width: 320, scale: 1.4);
    await save(tester, dark, 'history-compact-dark-large-text');
    await tester.tap(find.byKey(const ValueKey('history-compact-switch')));
    await tester.pumpAndSettle();
    await save(tester, dark, 'history-expanded-dark-large-text');
    expect(tester.takeException(), isNull);
  });
}
