import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase project configuration for the "hello-82bf9" project (see
/// https://console.firebase.google.com/project/hello-82bf9).
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for this platform. '
          'Run `flutterfire configure` to add other platforms.',
        );
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyCEfR5H68krQG3f21bZDl1JhDBvaZjUTRU',
    appId: '1:227063183986:web:1bedc1dde53d82c048e0eb',
    messagingSenderId: '227063183986',
    projectId: 'hello-82bf9',
    authDomain: 'hello-82bf9.firebaseapp.com',
    storageBucket: 'hello-82bf9.firebasestorage.app',
    measurementId: 'G-6JSVQTNHLW',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyCxn-3mOyrSJJ8-Y6CVtTNyyfwMEabewJI',
    appId: '1:227063183986:android:fccccea94291a74c48e0eb',
    messagingSenderId: '227063183986',
    projectId: 'hello-82bf9',
    storageBucket: 'hello-82bf9.firebasestorage.app',
  );
}
