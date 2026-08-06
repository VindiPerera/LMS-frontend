import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase project configuration for the "hello-82bf9" project (see
/// https://console.firebase.google.com/project/hello-82bf9).
///
/// Remaining setup on that project, if not done already:
/// 1. Authentication → Sign-in method → enable Email/Password and Google.
/// 2. Firestore Database → create it (production mode) and deploy
///    hello-firebase/firestore.rules + firestore.indexes.json.
/// 3. Storage → get started (production mode) and deploy
///    hello-firebase/storage.rules.
/// 4. For push notifications: Project settings → Cloud Messaging → "Web
///    configuration" → generate a key pair, then put it in
///    lib/services/push_notification_service.dart's `kFcmVapidKey`.
///    web/firebase-messaging-sw.js also needs this same config pasted in
///    (it's a plain JS file that can't import this Dart file).
///
/// This app only targets Flutter Web right now (see hello-frontend's setup
/// so far). If you later add Android/iOS/macOS, run `flutterfire configure`
/// instead of hand-editing this file — it'll regenerate all platform blocks
/// for you from the same project.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    throw UnsupportedError(
      'DefaultFirebaseOptions have only been configured for web in this '
      'project so far. Run `flutterfire configure` to add Android/iOS/macOS.',
    );
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
}
