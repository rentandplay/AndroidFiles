import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rent_and_play_app/models/item_model.dart';
import 'package:rent_and_play_app/screens/user/checkout_screen.dart';
import 'package:rent_and_play_app/services/auth_service.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';
import 'package:rent_and_play_app/services/server_clock.dart';
import 'package:rent_and_play_app/theme/app_theme.dart';
import 'widget_test.dart' show SignedOutAuth;

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'guest-user';
}

class _GuestAuth extends AuthService {
  @override
  User? get currentUser => _FakeUser();
}

class _DurationTestApi extends MobileApiService {
  _DurationTestApi({
    this.opensAt = '08:00',
    this.closesAt = '20:00',
  });

  final String opensAt;
  final String closesAt;
  final quotedMinutes = <int>[];

  @override
  Future<Map<String, dynamic>> quoteRental(
    String id,
    int minutes, {
    String? stockGroupId,
    DateTime? scheduledStartAt,
  }) async {
    quotedMinutes.add(minutes);
    return {
      'rental_fee': (minutes / 60) * 50,
      'billed_minutes': minutes,
      'requested_minutes': minutes,
      'overtime_rate': 50,
    };
  }

  @override
  Future<Map<String, dynamic>> paymentInstructions() async => {
        'accept_cash': true,
      };

  @override
  Future<Map<String, dynamic>> businessSettings() async => {
        'settings': {
          'opens_at': opensAt,
          'closes_at': closesAt,
          'timezone': 'Asia/Manila',
        },
      };

  @override
  Future<Map<String, dynamic>> terms() async => {
        'rental_terms': 'Resort rental terms apply.',
        'rental_terms_version': 'test-v1',
      };

  @override
  Stream<Map<String, dynamic>> watchRentalEvents() => const Stream.empty();
}

final _volleyballItem = ItemModel(
  id: 'vb-1',
  name: 'Volleyball',
  category: 'Sports',
  description: 'Resort volleyball set',
  rateText: '₱50 / hour',
  rateHourly: 50,
  imageUrl: 'assets/images/logo_rent_and_play.png',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = SignedOutAuth();
  });

  tearDown(() {
    ServerClock.instance.synchronize(DateTime.now().toUtc());
  });

  testWidgets(
      'supports 22 hrs whole day, 24 hrs (1 day), and multi-day custom durations',
      (tester) async {
    ServerClock.instance.synchronize(DateTime.utc(2026, 11, 10, 6, 0)); // 2 PM Manila
    final api = _DurationTestApi();
    final auth = _GuestAuth();
    addTearDown(auth.dispose);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: CheckoutScreen(item: _volleyballItem, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Preserves single initial TextFormField (phone number) contract
    expect(find.byType(TextFormField), findsOneWidget);

    // 22 hrs (Whole day) chip is visible and selectable
    final wholeDayChip = find.widgetWithText(ChoiceChip, '22 hrs (Whole day)');
    expect(wholeDayChip, findsOneWidget);
    await tester.ensureVisible(wholeDayChip);
    await tester.tap(wholeDayChip);
    await tester.pumpAndSettle();
    expect(api.quotedMinutes.last, 1320);

    // Starting at 2:00 PM, 22 hrs returns at 12:00 PM next day (inside 8 AM - 8 PM)
    expect(find.textContaining('Estimated return: Wed, Nov 11'), findsOneWidget);
    expect(find.textContaining('Return falls outside store hours'), findsNothing);

    // 24 hrs (1 day) chip works
    final oneDayChip = find.widgetWithText(ChoiceChip, '24 hrs (1 day)');
    expect(oneDayChip, findsOneWidget);
    await tester.ensureVisible(oneDayChip);
    await tester.tap(oneDayChip);
    await tester.pumpAndSettle();
    expect(api.quotedMinutes.last, 1440);

    // Opening Custom time defaults to 2 days (48 hrs) and shows presets & steppers
    final customChip = find.widgetWithText(ChoiceChip, 'Custom time...');
    await tester.ensureVisible(customChip);
    await tester.tap(customChip);
    await tester.pumpAndSettle();
    expect(api.quotedMinutes.last, 2880);
    expect(find.text('Custom: 48 hrs (2 days)'), findsOneWidget);

    // Tap 7 days (Max) preset -> quotes 10080 minutes
    final sevenDaysChip = find.widgetWithText(ActionChip, '7 days (Max)');
    await tester.ensureVisible(sevenDaysChip);
    await tester.tap(sevenDaysChip);
    await tester.pumpAndSettle();
    expect(api.quotedMinutes.last, 10080);

    // Decrement days from 7 to 6 -> quotes 6 days (8640 minutes) after debounce
    final minusIcons = find.byIcon(Icons.remove_circle_outline_rounded);
    await tester.ensureVisible(minusIcons.first);
    await tester.tap(minusIcons.first);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(api.quotedMinutes.last, 8640);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Type hours dialog validates unreasonable hour inputs',
      (tester) async {
    ServerClock.instance.synchronize(DateTime.utc(2026, 11, 10, 6, 0));
    final api = _DurationTestApi();
    final auth = _GuestAuth();
    addTearDown(auth.dispose);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          home: CheckoutScreen(item: _volleyballItem, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Custom time...'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom time...'));
    await tester.pumpAndSettle();

    final typeHours = find.text('Type hours');
    await tester.ensureVisible(typeHours);
    await tester.tap(typeHours);
    await tester.pumpAndSettle();

    // 0 hours rejected
    final hoursField = find.widgetWithText(TextFormField, 'Total hours');
    await tester.enterText(hoursField, '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Minimum rental duration is 1 hour.'), findsOneWidget);

    // > 168 hours rejected
    await tester.enterText(hoursField, '200');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Maximum is 168 hours (7 days). Contact resort staff for longer stays.'),
      findsOneWidget,
    );

    // Valid 36 hours accepted
    await tester.enterText(hoursField, '36');
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(api.quotedMinutes.last, 2160);
    expect(find.text('Custom: 36 hrs (1 d 12 hrs)'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'flags after-hours return guidance and validates out-of-hours schedule',
      (tester) async {
    // 2:00 PM Manila
    ServerClock.instance.synchronize(DateTime.utc(2026, 11, 10, 6, 0));
    final api = _DurationTestApi(opensAt: '08:00', closesAt: '20:00');
    final auth = _GuestAuth();
    addTearDown(auth.dispose);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: MaterialApp(
          home: CheckoutScreen(item: _volleyballItem, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pick 8 hrs from 2:00 PM -> 10:00 PM return (outside 8 AM - 8 PM)
    final eightHoursChip = find.widgetWithText(ChoiceChip, '8 hrs');
    await tester.ensureVisible(eightHoursChip);
    await tester.tap(eightHoursChip);
    await tester.pumpAndSettle();
    expect(find.textContaining('Return falls outside store hours (8:00 AM – 8:00 PM)'),
        findsOneWidget);

    // Move clock to 9:00 PM Manila (closed), pick scheduled start (defaults +15m -> 9:15 PM)
    ServerClock.instance.synchronize(DateTime.utc(2026, 11, 10, 13, 0));
    await tester.ensureVisible(find.text('Rent now'));
    await tester.tap(find.text('Rent now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      find.text('Start time must be within store hours (8:00 AM – 8:00 PM).'),
      findsWidgets,
    );
    // Accept terms, Send button remains disabled due to invalid store-hours schedule
    final agreement = find.byKey(const ValueKey('rental-terms-acceptance'));
    await tester.ensureVisible(agreement);
    await tester.tap(agreement);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send rental request'))
          .onPressed,
      isNull,
    );

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'custom duration panel fits 320px narrow screens at 1.3x text scale without overflow',
      (tester) async {
    ServerClock.instance.synchronize(DateTime.utc(2026, 11, 10, 6, 0));
    for (final dark in [false, true]) {
      final api = _DurationTestApi();
      final auth = _GuestAuth();
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: CheckoutScreen(item: _volleyballItem, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Custom time...'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Custom time...'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'dark=$dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      auth.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
