import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NotificationSound {
  static const channel = MethodChannel('rent_and_play/notification_sound');

  static Future<void> play() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('play');
    } on PlatformException {
      // Sound failures must not interrupt inbox updates.
    } on MissingPluginException {
      // Other platforms and older native builds still show visual alerts.
    }
  }
}
