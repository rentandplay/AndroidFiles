import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'providers/theme_provider.dart';
import 'screens/startup_router.dart';
import 'services/notification_service.dart';
import 'widgets/notification_widgets.dart';

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

@pragma('vm:entry-point')
Future<void> rentalNotificationBackground(RemoteMessage message) async {
  await _ensureFirebaseInitialized();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();

  await _ensureFirebaseInitialized();

  FirebaseMessaging.onBackgroundMessage(rentalNotificationBackground);
  runApp(const RentAndPlayApp());
}

class RentAndPlayApp extends StatelessWidget {
  const RentAndPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, RentalNotificationService>(
            create: (_) => RentalNotificationService(),
            update: (_, auth, notifications) =>
                notifications!..setSession(auth.currentUser?.uid)),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: rentalNavigatorKey,
            scaffoldMessengerKey: rentalMessengerKey,
            builder: (_, child) => RentalNotificationHost(child: child!),
            title: 'Rent & Play',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const StartupRouter(),
          );
        },
      ),
    );
  }
}
