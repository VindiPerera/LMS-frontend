import 'package:flutter/material.dart';

import '../screens/connect/partner_profile_screen.dart';
import '../screens/hellotalk/chat_detail_screen.dart';
import '../screens/moments/post_detail_screen.dart';
import '../screens/voiceroom/open_voice_room.dart' as voice_room_nav;
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

  /// Deep-links to [uid]'s profile — a legacy friend-request/accept push
  /// notification tap (see push_notification_service.dart; the app no
  /// longer sends these, but an old one could still be tapped from the
  /// system tray shortly after an update), or a QR/link tap
  /// (deep_link_service.dart). PartnerProfileScreen needs a full AppUser, so
  /// (unlike the old FriendProfileScreen, which loaded the user itself) this
  /// fetches first — fire-and-forget from the notification/link tap handler,
  /// same as [openChat].
  static Future<void> openProfile(String uid) async {
    if (uid.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    try {
      final user = await PartnerService.fetchPartner(uid);
      navigator.push(
        MaterialPageRoute(builder: (_) => PartnerProfileScreen(initial: user)),
      );
    } catch (e) {
      debugPrint('NavigationService.openProfile($uid) failed: $e');
    }
  }

  /// Deep-links to voice room [roomId] — from a Voice Room invite
  /// notification. Fetches the room first since VoiceRoomDetailScreen needs
  /// the full [VoiceRoom], not just its id; silently no-ops if the room
  /// already ended by the time the notification is tapped. Goes through
  /// screens/voiceroom/open_voice_room.dart like every other "open this
  /// room" entry point in the app, so a still-banned user gets the same
  /// "you can't join this room" dialog here too instead of the room
  /// briefly flashing open from a tapped notification.
  static Future<void> openVoiceRoom(String roomId) async {
    if (roomId.isEmpty) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    try {
      final room = await VoiceRoomService.fetchRoom(roomId);
      if (room == null || !context.mounted) return;
      await voice_room_nav.openVoiceRoom(context, room);
    } catch (e) {
      debugPrint('NavigationService.openVoiceRoom($roomId) failed: $e');
    }
  }
}
