import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/voiceroom.dart';
import 'auth_service.dart';

/// All Firestore access for `voiceRooms/{roomId}` — a user's live/active
/// voice room. Screens never talk to Firestore directly for this; see
/// lib/screens/voiceroom/voiceroom_screen.dart (the browse feed + "Start Room
/// Now"), lib/screens/connect/partner_profile_screen.dart (a profile's
/// "Created VoiceRoom" card), and lib/screens/hellotalk/chat_list_screen.dart
/// (the "you're hosting" banner atop Chat) for the three places a room
/// surfaces.
///
/// Only one active room per host is allowed — [createRoom] automatically
/// ends any previous room that host was still hosting, since nobody can
/// credibly be "live" in two rooms at once. Ending a room is a soft update
/// (`isActive: false`), never a delete, matching how moments are
/// soft-deleted elsewhere in the app.
class VoiceRoomService {
  static CollectionReference<Map<String, dynamic>> get _rooms =>
      FirebaseFirestore.instance.collection('voiceRooms');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Rooms this device is currently allowed to see: 'public' plus, if
  /// signed in, its own uid — matches firestore.rules'
  /// `audience.hasAny(['public', uid])` read check exactly, and has to be a
  /// real query filter (not just a client-side .where check after the
  /// fact) or Firestore rejects the whole query outright as unprovable
  /// against the rules — see MomentService._audienceKeysForReader, which
  /// this mirrors. Every room created today has `audience: ['public']`, so
  /// 'public' alone would now cover every current room; the extra own-uid
  /// key is kept only so a user's own room stays visible if it's one of the
  /// old restricted-audience documents from before rooms went public-only.
  static List<String> _audienceKeysForReader() {
    final uid = _uid;
    return uid == null || uid.isEmpty ? const ['public'] : ['public', uid];
  }

  /// Live feed of every currently-active room this user may see, newest
  /// first — the main Voice tab feed. Every room is public, so this shows
  /// all of them; [_audienceKeysForReader] additionally covers any
  /// restricted-audience room left over from before rooms went public-only.
  /// Needs the `isActive` + `audience` (CONTAINS) + `createdAt` composite
  /// index in firestore.indexes.json deployed (`firebase deploy --only
  /// firestore:indexes`) — without it Firestore rejects this query outright
  /// and every room silently vanishes from the feed instead of erroring
  /// loudly, hence the debugPrint below rather than a bare swallow.
  static Stream<List<VoiceRoom>> streamActiveRooms({int limit = 30}) {
    return _rooms
        .where('isActive', isEqualTo: true)
        .where('audience', arrayContainsAny: _audienceKeysForReader())
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(VoiceRoom.fromFirestore).toList())
        .handleError((e) {
          debugPrint('VoiceRoomService.streamActiveRooms failed (showing no rooms): $e');
          return <VoiceRoom>[];
        });
  }

  /// The room [userId] is currently hosting, or null if they don't have one
  /// active right now. Used by the profile screen's voice-room card and the
  /// Chat tab's "you're hosting" banner.
  static Stream<VoiceRoom?> streamActiveRoomForUser(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _rooms
        .where('hostId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .where('audience', arrayContainsAny: _audienceKeysForReader())
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : VoiceRoom.fromFirestore(snap.docs.first))
        .handleError((_) => null);
  }

  /// Convenience for the signed-in user's own active room.
  static Stream<VoiceRoom?> streamMyActiveRoom() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return streamActiveRoomForUser(uid);
  }

  /// One-time fetch of a single room by id, e.g. hydrating a Voice Room
  /// invite notification deep link (NavigationService.openVoiceRoom) into
  /// the full [VoiceRoom] object VoiceRoomDetailScreen needs. Returns null
  /// if it no longer exists, or (unlike a list query, a single get() doesn't
  /// get rejected outright — it's just denied) if this device isn't in the
  /// room's `audience`, e.g. an invite that was later revoked.
  static Future<VoiceRoom?> fetchRoom(String roomId) async {
    if (roomId.isEmpty) return null;
    try {
      final doc = await _rooms.doc(roomId).get();
      if (!doc.exists) return null;
      return VoiceRoom.fromFirestore(doc);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  /// Live updates for a single room — VoiceRoomDetailScreen uses this to
  /// notice when its own room gets ended (isActive flips to false) while
  /// it's still open, so it can auto-pop everyone still inside instead of
  /// leaving them stranded on a dead room. Null once the room no longer
  /// exists (shouldn't normally happen — rooms are soft-deleted — but keeps
  /// this safe if one ever is removed outright).
  static Stream<VoiceRoom?> streamRoom(String roomId) {
    if (roomId.isEmpty) return Stream.value(null);
    return _rooms
        .doc(roomId)
        .snapshots()
        .map((doc) => doc.exists ? VoiceRoom.fromFirestore(doc) : null)
        .handleError((e) {
          debugPrint('VoiceRoomService.streamRoom failed: $e');
          return null;
        });
  }

  /// Creates a new room hosted by the signed-in user. Every room this app
  /// creates is public — listed in everyone's browse feed and joinable by
  /// any signed-in user; there is no private-room option.
  static Future<VoiceRoom> createRoom({
    required String title,
    String tag = 'General',
    String category = 'EN',
  }) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null) {
      throw StateError('You must be signed in to start a voice room.');
    }
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw StateError('Give your room a topic before starting it.');
    }

    await _endAllActiveRoomsFor(uid);

    final draft = VoiceRoom(
      hostId: uid,
      title: cleanTitle,
      hostName: user.name,
      hostAvatar: user.avatarUrl,
      hostFlag: user.countryFlag,
      category: category,
      tag: tag.trim().isEmpty ? 'General' : tag.trim(),
      // 0, not 1 — RoomParticipantService.join bumps this to 1 the instant
      // VoiceRoomDetailScreen opens for the host (its initState always
      // follows createRoom immediately), so it stays the single place that
      // increments/decrements this count instead of double-counting here.
      participantCount: 0,
      isCreator: true,
      // Always public — visible to, and joinable by, any signed-in user.
      audience: const ['public'],
    );

    final ref = _rooms.doc();
    await ref.set(draft.toCreateMap());
    final snap = await ref.get();
    return VoiceRoom.fromFirestore(snap);
  }

  /// Ends [roomId] so it stops showing up anywhere. Only the host or a live
  /// moderator may do this (also enforced by firestore.rules) — callers
  /// should guard the UI action on RoomParticipant.canModerate too, rather
  /// than relying only on the rules rejection.
  static Future<void> endRoom(String roomId) async {
    if (roomId.isEmpty) return;
    await _rooms.doc(roomId).update({'isActive': false});
  }

  static Future<void> _endAllActiveRoomsFor(String uid) async {
    final existing = await _rooms
        .where('hostId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .get();
    if (existing.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in existing.docs) {
      batch.update(doc.reference, {'isActive': false});
    }
    await batch.commit();
  }
}
