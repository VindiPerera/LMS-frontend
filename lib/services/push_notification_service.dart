import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'navigation_service.dart';

/// Web Push certificate key, from Firebase Console → Project settings →
/// Cloud Messaging → "Web configuration" → Generate key pair. Only needed
/// for receiving push notifications on Flutter Web; leave blank to skip
/// FCM setup without errors (initialize() just no-ops).
const String kFcmVapidKey = '';

const AndroidNotificationChannel _momentsChannel = AndroidNotificationChannel(
  'moments_channel',
  'Moments',
  description: 'Likes, comments, reshares and mentions on your moments.',
  importance: Importance.high,
);

/// Background/terminated FCM messages arrive in a separate isolate, so this
/// has to be a top-level (or static) function — see main.dart, where it's
/// registered with `FirebaseMessaging.onBackgroundMessage`. It can't safely
/// touch app state or navigate; tapping the resulting system notification is
/// what actually triggers navigation, via onMessageOpenedApp/getInitialMessage
/// below once the app is back in the foreground.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.messageId}');
}

/// Owns FCM registration (permission, token, foreground/background/
/// terminated handlers) and showing local notification banners while the
/// app is in the foreground. The in-app notification *feed* (Firestore
/// `notifications/{uid}/items`) is a separate concern — see
/// notification_service.dart.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _localNotifications = FlutterLocalNotificationsPlugin();
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
      await _initLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = kIsWeb
          ? await messaging.getToken(vapidKey: kFcmVapidKey)
          : await messaging.getToken();
      await _saveToken(token);
      messaging.onTokenRefresh.listen(_saveToken);

      // Foreground: FCM doesn't show a system banner itself, so show one
      // via flutter_local_notifications.
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // App was backgrounded, user tapped the system notification.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _openFromData(_stringifyData(message.data));
      });

      // App was fully terminated, user tapped the system notification to
      // launch it.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _openFromData(_stringifyData(initialMessage.data));
      }
    } catch (e) {
      debugPrint('Push notification setup failed (continuing without it): $e');
      _initialized = false;
    }
  }

  Map<String, String> _stringifyData(Map<String, dynamic> data) =>
      data.map((key, value) => MapEntry(key, value?.toString() ?? ''));

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          _openFromData(data.map((k, v) => MapEntry(k, v?.toString() ?? '')));
        } catch (_) {
          // Malformed/legacy payload — nothing to navigate to.
        }
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_momentsChannel);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _momentsChannel.id,
          _momentsChannel.name,
          channelDescription: _momentsChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _openFromData(Map<String, String> data) {
    final postId = data['postId'];
    if (postId != null && postId.isNotEmpty) {
      NavigationService.openPost(postId);
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
