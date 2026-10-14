import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:rent_and_play_app/firebase_options.dart';
import 'package:rent_and_play_app/services/mobile_api_service.dart';

// Read-only acceptance check against the same laptop API used by the web.
// This never creates accounts, rentals, payments, or notifications.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const origin = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000/api');
  testWidgets('Android reaches shared Firebase catalog with ESP32 on standby',
      (_) async {
    await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 30));
    // Keep device failures attributable to one step instead of waiting for the
    // whole integration-test timeout with no indication of the stalled call.
    debugPrint('Device smoke: Firebase initialized.');
    expect(Firebase.app().options.projectId, 'rent-and-play');
    final client = http.Client();
    try {
      final health = await client
          .get(Uri.parse('$origin/health'))
          .timeout(const Duration(seconds: 20));
      debugPrint('Device smoke: API health returned ${health.statusCode}.');
      expect(health.statusCode, 200);
      final status = jsonDecode(health.body) as Map;
      expect(status['database'], true);
      expect(status['firebaseProjectId'], Firebase.app().options.projectId);
      debugPrint('Device smoke: reading mobile catalog.');
      final catalog = await MobileApiService.instance
          .catalog()
          .timeout(const Duration(seconds: 30));
      debugPrint('Device smoke: catalog returned ${catalog.length} groups.');
      expect(catalog, isNotEmpty);
      final equipment = catalog
          .firstWhere((row) => (row['item_code'] ?? '').toString().isNotEmpty);
      debugPrint('Device smoke: resolving ${equipment['item_code']}.');
      final resolved = await MobileApiService.instance
          .resolveEquipment(equipment['item_code'].toString())
          .timeout(const Duration(seconds: 30));
      debugPrint('Device smoke: equipment code resolved.');
      expect(resolved['stock_group_id'] ?? resolved['id'],
          equipment['stock_group_id'] ?? equipment['id']);
      final terminal = await client
          .get(Uri.parse('$origin/terminals/standby-check/pending'))
          .timeout(const Duration(seconds: 20));
      debugPrint(
          'Device smoke: ESP32 standby returned ${terminal.statusCode}.');
      expect(terminal.statusCode, 409);
      expect(jsonDecode(terminal.body)['error'], contains('standby'));
      debugPrint('Device smoke: all checks passed.');
    } finally {
      client.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
