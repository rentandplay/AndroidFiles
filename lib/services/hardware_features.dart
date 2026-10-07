/// Kept for future hardware integration. Current rentals use the admin API.
abstract final class HardwareFeatures {
  static const enabled = false;
  static void requireEnabled() {
    if (!enabled) {
      throw StateError(
          'ESP32 is on standby. Use the admin rental and return desk.');
    }
  }
}
