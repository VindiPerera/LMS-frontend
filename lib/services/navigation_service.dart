import 'package:flutter/material.dart';

import '../screens/friends/friend_profile_screen.dart';
import '../screens/hellotalk/chat_detail_screen.dart';
import '../screens/moments/post_detail_screen.dart';
import '../screens/voiceroom/voice_room_detail_screen.dart';
import 'partner_service.dart';
import 'voice_room_service.dart';

/// A global [NavigatorState] key, assigned to `MaterialApp.navigatorKey` in
/// main.dart. Needed because push notifications can be tapped while there's
/// no relevant `BuildContext` at hand — the notification tap handlers live
/// in push_notification_service.dart, well outside the widget tree.
class NavigationService {
  NavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Deep-links to a single moment, e.g. from a tapped push notification or
  /// a notification_screen.dart row.
  static void openPost(String postId) {
    if (postId.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
    );
  }

  /// Deep-links to a 1:1 chat thread with [otherUid], e.g. from a tapped
  /// "new message" push notification. ChatDetailScreen needs the other
  /// user's full profile (not just their uid), so this does one Firestore
  /// read first — fire-and-forget from the notification tap handler, same
  /// as [openPost].
  static Future<void> openChat(String otherUid) async {
    if (otherUid.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    try {
      final user = await PartnerService.fetchPartner(otherUid);
      navigator.push(
        MaterialPageRoute(builder: (_) => ChatDetailScreen(user: user)),
      );
    } catch (e) {
      debugPrint('NavigationService.openChat($otherUid) failed: $e');
    }
  }

  /// Deep-links to [uid]'s profile — friend request/accept notifications.
  /// FriendProfileScreen loads the user itself, so no fetch needed here.
  static void openFriendProfile(String uid) {
    if (uid.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(friendId: uid, source: 'notification'),
      ),
    );
  }

  /// Deep-links to voice room [roomId] — from a Voice Room invite
  /// notification. Fetches the room first since VoiceRoomDetailScreen needs
  /// the full [VoiceRoom], not just its id; silently no-ops if the room
  /// already ended by the time the notification is tapped.
  static Future<void> openVoiceRoom(String roomId) async {
    if (roomId.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    try {
      final room = await VoiceRoomService.fetchRoom(roomId);
      if (room == null) return;
      navigator.push(
        MaterialPageRoute(builder: (_) => VoiceRoomDetailScreen(room: room)),
      );
    } catch (e) {
      debugPrint('NavigationService.openVoiceRoom($roomId) failed: $e');
    }
  }
}
