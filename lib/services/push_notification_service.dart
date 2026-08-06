import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Web Push certificate key, from Firebase Console → Project settings →
/// Cloud Messaging → "Web configuration" → Generate key pair. Only needed
/// for receiving push notifications on Flutter Web; leave blank to skip
/// FCM setup without errors (initialize() just no-ops).
const String kFcmVapidKey = '';

/// Client-side push notification registration only — requests permission,
/// grabs this device's FCM token and stores it on the user's profile, and
/// logs incoming foreground messages.
///
/// Actually *sending* notifications (e.g. "new message from X") needs a
/// server-side trigger — a Cloud Function watching Firestore, or another
/// backend calling the FCM Admin API — which isn't set up here; this only
/// wires up the receiving end so that piece can be added later without
/// touching the client again.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kFcmVapidKey.isEmpty && kIsWeb) {
      // Not configured yet — skip silently rather than throwing on every
      // sign-in (see this file's setup comment / lib/firebase_options.dart).
      return;
    }
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = kIsWeb
          ? await messaging.getToken(vapidKey: kFcmVapidKey)
          : await messaging.getToken();
      await _saveToken(token);

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          'FCM foreground message: ${message.notification?.title ?? message.data}',
        );
      });
    } catch (e) {
      debugPrint('Push notification setup failed (continuing without it): $e');
      _initialized = false;
    }
  }

  Future<void> _saveToken(String? token) async {
    if (token == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
      });
    } catch (_) {
      // Non-critical — the user just won't be reachable by push yet.
    }
  }
}
