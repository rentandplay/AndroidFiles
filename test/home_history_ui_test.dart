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
import 'package:rent_and_play_app/widgets/mobile_controls.dart';
import 'package:rent_and_play_app/screens/user/active_rentals_screen.dart';
import 'package:rent_and_play_app/screens/auth/login_screen.dart';

import 'widget_test.dart' show SignedOutAuth;

class _Customer extends Fake implements User {
  _Customer([this.id = 'customer']);
  final String id;
  @override
  String get uid => id;
  @override
  String get displayName => 'Jhon Saberon';
}

class _CustomerAuth extends AuthService {
  User? _user = _Customer();
  @override
  User? get currentUser => _user;
  @override
  Future<UserModel?> getCurrentUserModel() async => null;

  void changeUser(String? id) {
    _user = id == null ? null : _Customer(id);
    notifyListeners();
  }
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
  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => const Stream.empty();
}

RentalModel _rental(String id, String name,
        {double due = 0, double refund = 0, String status = 'COMPLETED'}) =>
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
      status: status,
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
      bool browse = false,
      bool rentals = false,
      AuthService? auth,
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
        create: (_) => auth ?? _CustomerAuth(),
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
          home: Consumer<AuthService>(
              builder: (context, service, _) => Scaffold(
                    body: screen,
                    bottomNavigationBar: service.currentUser == null
                        ? null
                        : NavigationBar(
                            height: 72,
                            selectedIndex: history
                                ? 3
                                : browse
                                    ? 1
                                    : rentals
                                        ? 2
                                        : 0,
                            destinations: _destinations,
                          ),
                  )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final imageContext = tester.element(find.byType(Scaffold).first);
    await tester.runAsync(() async {
      for (final image in {
        ...ItemModel.getInitialCatalog().map((item) => item.cleanImageUrl),
        'assets/images/logo_rent_and_play.png',
      }) {
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
      'Browse gates Saved by account and clears stale Saved filters on sign-out',
      (tester) async {
    final auth = _CustomerAuth()..changeUser(null);
    final source = ItemModel.getInitialCatalog();
    final api = _HomeApi()
      ..items = [
        source.firstWhere((item) => item.name == 'Badminton Set').toMap(),
        source.firstWhere((item) => item.name == 'Bicycle').toMap(),
        {
          ...source.firstWhere((item) => item.name == 'Jenga').toMap(),
          'status': 'unavailable',
          'available_quantity': 0
        },
      ];
    final capture =
        await render(tester, CatalogScreen(api: api), auth: auth, browse: true);
    final available = find.byKey(const ValueKey('catalog-available-filter'));
    final saved = find.byKey(const ValueKey('catalog-saved-filter'));
    expect(saved, findsNothing);
    expect(find.byTooltip('Save item'), findsNothing);
    expect(find.byTooltip('Remove from saved'), findsNothing);
    await tester.tap(available);
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsOneWidget);
    await save(tester, capture, 'browse-guest-light');

    auth.changeUser('customer');
    await tester.pumpAndSettle();
    expect(find.text('Saved (0)'), findsOneWidget);
    await tester.tap(find.byTooltip('Save item').first);
    await tester.pumpAndSettle();
    expect(find.text('Saved (1)'), findsOneWidget);
    await tester.tap(saved);
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    await save(tester, capture, 'browse-saved-light');

    auth.changeUser('another-customer');
    await tester.pumpAndSettle();
    expect(find.text('Saved (0)'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.byTooltip('Remove from saved'), findsNothing);
    await tester.tap(find.byTooltip('Save item').first);
    await tester.pumpAndSettle();
    await tester.tap(saved);
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);

    auth.changeUser(null);
    await tester.pumpAndSettle();
    expect(saved, findsNothing);
    expect(find.byTooltip('Save item'), findsNothing);
    expect(find.byTooltip('Remove from saved'), findsNothing);
    expect(find.text('2 items'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Browse selected filters and saved cards fit narrow screens with large text',
      (tester) async {
    final capture = await render(tester, CatalogScreen(api: _HomeApi()),
        browse: true, dark: true, width: 320, scale: 1.4);
    await tester.tap(find.byKey(const ValueKey('catalog-available-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save item').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('catalog-saved-filter')));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('Saved (1)'), findsOneWidget);
    expect(find.byTooltip('Remove from saved'), findsOneWidget);
    await save(tester, capture, 'browse-saved-dark-large-text');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Browse compact search clears results and sort menu changes equipment order',
      (tester) async {
    final template = ItemModel.getInitialCatalog().first;
    final api = _HomeApi()
      ..items = [
        template
            .copyWith(id: 'a', name: 'A unavailable', status: 'unavailable')
            .toMap(),
        template.copyWith(id: 'b', name: 'B available').toMap(),
      ];
    await render(tester, CatalogScreen(api: api), browse: true);
    expect(tester.getSize(find.byType(MobileSearchField)).height,
        lessThanOrEqualTo(52));
    expect(tester.getTopLeft(find.text('B available')).dx,
        lessThan(tester.getTopLeft(find.text('A unavailable')).dx));
    await tester.enterText(find.byType(TextField), 'B available');
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('2 items'), findsOneWidget);
    await tester.tap(find.byTooltip('Sort equipment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> && widget.value == 'name'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('A unavailable')).dx,
        lessThan(tester.getTopLeft(find.text('B available')).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Rentals search clears both the displayed query and filtered results',
      (tester) async {
    final api = _HomeApi()
      ..rentals = [
        _rental('1', 'Basketball', status: 'ACTIVE'),
        _rental('2', 'Pickleball Set', status: 'ACTIVE'),
        _rental('3', 'Badminton Set', status: 'ACTIVE'),
        _rental('4', 'Jenga', status: 'ACTIVE'),
      ];
    final capture =
        await render(tester, ActiveRentalsScreen(api: api), rentals: true);
    await tester.enterText(find.byType(TextField), 'Basketball');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 4 rentals'), findsOneWidget);
    await save(tester, capture, 'rentals-search-light');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Showing 1 of 4 rentals'), findsNothing);
    expect(find.text('Pickleball Set'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Login stays readable with large text and typing alone shows no validation errors',
      (tester) async {
    final auth = _CustomerAuth()..changeUser(null);
    final capture = await render(tester, const LoginScreen(), auth: auth);
    await save(tester, capture, 'login-light');
    await tester.enterText(find.byType(TextFormField).first, 'reynold');
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsNothing);
    expect(find.text('Please enter your password.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    final darkAuth = _CustomerAuth()..changeUser(null);
    final dark = await render(tester, const LoginScreen(),
        auth: darkAuth, dark: true, width: 320, scale: 1.4);
    await tester.enterText(find.byType(TextFormField).first, 'reynold');
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsNothing);
    await tester.scrollUntilVisible(find.text('Register'), 150,
        scrollable: getVerticalScroll());
    await tester.ensureVisible(find.text('Register'));
    await tester.pumpAndSettle();
    await save(tester, dark, 'login-large-text');
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.pumpAndSettle();
    await save(tester, dark, 'login-dark-validation');
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
    final toggle = find.byKey(const ValueKey('history-view-toggle'));
    expect(tester.widget<IconButton>(toggle).isSelected, isTrue);
    expect(find.text('Compact view'), findsNothing);
    expect(find.byTooltip('Show detailed view'), findsOneWidget);
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
    expect(tester.widget<IconButton>(toggle).isSelected, isFalse);
    expect(find.byTooltip('Show compact view'), findsOneWidget);
    expect(find.text('View details  ›'), findsOneWidget);
    expect(find.text('Basketball'), findsNothing);
    expect(find.text('Due ₱960.00'), findsOneWidget);
    expect(find.text('Refund ₱100.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());

    final dark = await render(tester, RentalHistoryScreen(api: api),
        history: true, dark: true, width: 320, scale: 1.4);
    await save(tester, dark, 'history-compact-dark-large-text');
    await tester.tap(find.byKey(const ValueKey('history-view-toggle')));
    await tester.pumpAndSettle();
    await save(tester, dark, 'history-expanded-dark-large-text');
    expect(tester.takeException(), isNull);
  });
}
