import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase project configuration for the "hello-52f9b" project (see
/// https://console.firebase.google.com/project/hello-52f9b).
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
    apiKey: 'AIzaSyDGyKutN7gNC4H65mM7C4KlZ7aJDC1ZLJE',
    appId: '1:867397619439:web:6f23e33a8ecb147f8c951a',
    messagingSenderId: '867397619439',
    projectId: 'hello-52f9b',
    authDomain: 'hello-52f9b.firebaseapp.com',
    storageBucket: 'hello-52f9b.firebasestorage.app',
    measurementId: 'G-GW7725VFLF',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyD5vjGEQp0GcyTsE82ebxynuDvKXWnUalU',
    appId: '1:867397619439:android:4d7b97f84ce616918c951a',
    messagingSenderId: '867397619439',
    projectId: 'hello-52f9b',
    storageBucket: 'hello-52f9b.firebasestorage.app',
  );
}
