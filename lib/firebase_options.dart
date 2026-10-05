import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAIrMFpHWYUmEXM2v1YqB092V-Mqj2Zokg',
    appId: '1:641470891206:web:804bb44b20952b4cd003c7',
    messagingSenderId: '641470891206',
    projectId: 'rent-and-play',
    authDomain: 'rent-and-play.firebaseapp.com',
    storageBucket: 'rent-and-play.firebasestorage.app',
    measurementId: 'G-SLWJC4EZ6C',
    databaseURL: 'https://rent-and-play-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAIrMFpHWYUmEXM2v1YqB092V-Mqj2Zokg',
    appId: '1:641470891206:android:804bb44b20952b4cd003c7',
    messagingSenderId: '641470891206',
    projectId: 'rent-and-play',
    storageBucket: 'rent-and-play.firebasestorage.app',
    databaseURL: 'https://rent-and-play-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAIrMFpHWYUmEXM2v1YqB092V-Mqj2Zokg',
    appId: '1:641470891206:ios:804bb44b20952b4cd003c7',
    messagingSenderId: '641470891206',
    projectId: 'rent-and-play',
    storageBucket: 'rent-and-play.firebasestorage.app',
    databaseURL: 'https://rent-and-play-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAIrMFpHWYUmEXM2v1YqB092V-Mqj2Zokg',
    appId: '1:641470891206:ios:804bb44b20952b4cd003c7',
    messagingSenderId: '641470891206',
    projectId: 'rent-and-play',
    storageBucket: 'rent-and-play.firebasestorage.app',
    databaseURL: 'https://rent-and-play-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAIrMFpHWYUmEXM2v1YqB092V-Mqj2Zokg',
    appId: '1:641470891206:web:804bb44b20952b4cd003c7',
    messagingSenderId: '641470891206',
    projectId: 'rent-and-play',
    authDomain: 'rent-and-play.firebaseapp.com',
    storageBucket: 'rent-and-play.firebasestorage.app',
    measurementId: 'G-SLWJC4EZ6C',
    databaseURL: 'https://rent-and-play-default-rtdb.firebaseio.com',
  );
}
