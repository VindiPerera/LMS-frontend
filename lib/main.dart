import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/auth/splash_screen.dart';
import 'services/deep_link_service.dart';
import 'services/navigation_service.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Must be registered before runApp, and firebaseMessagingBackgroundHandler
  // must stay a top-level function — see push_notification_service.dart.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Starts listening for QR-code/share-link taps immediately, so a
  // cold-start launch URI (Case A: app installed) is never missed — see
  // deep_link_service.dart. Doesn't block startup: resolving/navigating
  // happens once a Navigator (and, for a new link, a signed-in user) exist.
  unawaited(DeepLinkService.instance.initialize());

  runApp(const FaceTalkApp());
}

class FaceTalkApp extends StatelessWidget {
  const FaceTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceTalk',
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.navigatorKey,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
