import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Talks to hello-backend's NotificationController — the server-side hop
/// that makes push notifications possible without deploying Cloud
/// Functions (which requires Firebase's paid Blaze plan; this project
/// stays on the free Spark plan instead, see functions/index.js's header
/// comment for the full explanation). Laravel holds the Firebase service
/// account credentials that let it call FCM directly; nothing here does.
///
/// Every call is fire-and-forget from the caller's point of view: a failed
/// or unreachable backend should never block the Firestore write (sending
/// the chat message, friend request, etc.) that triggered it — so every
/// method here swallows its own errors after logging them.
class NotificationApiService {
  /// Registers/refreshes the signed-in device's FCM token. Called from
  /// push_notification_service.dart alongside (not instead of) its
  /// existing Firestore users/{uid}.fcmToken write.
  static Future<void> saveToken({required String uid, required String token}) async {
    if (uid.isEmpty || token.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/fcm-token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'uid': uid, 'token': token}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('NotificationApiService.saveToken failed (non-fatal): $e');
    }
  }

  /// Sends a push notification to [recipientUid]. [data] should include at
  /// least a `type` key (`chat` / `friendRequest` / `friendAccept` /
  /// `voiceroom` / `comment` / `reshare` / `mention`) — the backend uses it
  /// to route to the matching Android notification channel, and the
  /// client's push_notification_service.dart uses it again on tap to
  /// decide where to navigate.
  static Future<void> sendPush({
    required String recipientUid,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    if (recipientUid.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/notifications/push'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'recipient_uid': recipientUid,
              'title': title,
              'body': body,
              'data': data,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // Never rethrow — a missed push is far less bad than failing the
      // chat message/friend request/etc. that triggered it.
      debugPrint('NotificationApiService.sendPush($recipientUid) failed (non-fatal): $e');
    }
  }
}
