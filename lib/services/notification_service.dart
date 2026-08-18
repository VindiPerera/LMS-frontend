import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/notification_model.dart';
import 'auth_service.dart';

/// Firestore access for `notifications/{uid}/items`. Distinct from
/// push_notification_service.dart, which owns FCM registration and showing
/// local notification banners — this is purely the in-app notification
/// feed (notification_screen.dart, the Moments tab badge).
class NotificationService {
  static CollectionReference<Map<String, dynamic>>? _items(String? uid) {
    if (uid == null || uid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items');
  }

  static String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  static Stream<List<NotificationModel>> streamNotifications() {
    final items = _items(_currentUid);
    if (items == null) return const Stream<List<NotificationModel>>.empty();
    return items
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(NotificationModel.fromFirestore).toList());
  }

  /// Unread count, for the Moments tab badge (lib/widgets/notification_badge.dart).
  static Stream<int> streamUnreadCount() {
    final items = _items(_currentUid);
    if (items == null) return Stream.value(0);
    return items
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  static Future<void> markAsRead(String notifId) async {
    final items = _items(_currentUid);
    if (items == null || notifId.isEmpty) return;
    await items.doc(notifId).update({'isRead': true});
  }

  static Future<void> markAllAsRead() async {
    final items = _items(_currentUid);
    if (items == null) return;
    final unread = await items.where('isRead', isEqualTo: false).get();
    if (unread.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Invites [recipientId] to the signed-in user's live voice room.
  ///
  /// This does NOT write the notification itself — `notifications/{uid}/
  /// items` is owner-write-only (see firestore.rules), so no client can
  /// ever drop something into another user's feed directly, same as every
  /// other notification type in this app. Instead this writes a
  /// `voiceRoomInvites` doc; functions/index.js's onVoiceRoomInviteCreate
  /// (Admin SDK, bypasses rules) turns that into the real notification and
  /// push for [recipientId].
  static Future<void> inviteToVoiceRoom({
    required String recipientId,
    required String roomId,
  }) async {
    final hostId = _currentUid;
    final host = AuthService.instance.currentUser;
    if (hostId == null || host == null || recipientId.isEmpty || roomId.isEmpty) return;

    await FirebaseFirestore.instance.collection('voiceRoomInvites').add({
      'hostId': hostId,
      'hostName': host.name,
      'hostAvatar': host.avatarUrl,
      'recipientId': recipientId,
      'roomId': roomId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
