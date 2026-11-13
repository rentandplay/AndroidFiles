import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rent_and_play_app/services/notification_sound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationSound.channel, null);
  });
  test('Android notification sound invokes its native playback method',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NotificationSound.channel, (call) async {
      calls.add(call);
      return null;
    });
    await NotificationSound.play();
    expect(calls.single.method, 'play');
  });
  test('missing native audio support does not interrupt the inbox', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(NotificationSound.play(), completes);
  });
}
