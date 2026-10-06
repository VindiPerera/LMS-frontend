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
    var user = AuthService.instance.currentUser;
    if (uid == null || user == null) {
      throw StateError('You must be signed in to start a voice room.');
    }
    // Refresh user from Firestore if avatar is empty to pick up any freshly uploaded photo
    if (user.avatarUrl.isEmpty) {
      final refreshed = await AuthService.instance.refreshCurrentUser();
      if (refreshed != null) user = refreshed;
    }
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw StateError('Give your room a topic before starting it.');
    }

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
    // IMPORTANT: end old rooms FIRST, then create the new one — never
    // concurrently. If both writes ran in parallel (Future.wait), there was
    // a real race where the new room's document could be committed to
    // Firestore before _endAllActiveRoomsFor's query snapshot was taken,
    // causing the new room itself to appear in `existing.docs` and be
    // immediately set isActive: false — triggering the "This room has
    // ended." snackbar the moment VoiceRoomDetailScreen opened.
    await _endAllActiveRoomsFor(uid);
    await ref.set(draft.toCreateMap());
    // No read-back of the doc we just wrote: VoiceRoomDetailScreen's own
    // streamRoom subscription (see its initState) takes over moments later
    // anyway, and everything it needs before that — id (ref.id) and hostId
    // (uid) — is already known here, so re-fetching would just be a second
    // round-trip for data this call already has.
    return VoiceRoom(
      id: ref.id,
      hostId: draft.hostId,
      title: draft.title,
      hostName: draft.hostName,
      hostAvatar: draft.hostAvatar,
      hostFlag: draft.hostFlag,
      category: draft.category,
      tag: draft.tag,
      coverGradientSeed: draft.coverGradientSeed,
      participantAvatars: draft.participantAvatars,
      participantCount: draft.participantCount,
      isTop: draft.isTop,
      isCreator: draft.isCreator,
      isActive: true,
      audience: draft.audience,
      createdAt: DateTime.now(),
    );
  }

  /// Ends [roomId] so it stops showing up anywhere. Only the host or a live
  /// moderator may do this (also enforced by firestore.rules) — callers
  /// should guard the UI action on RoomParticipant.canModerate too, rather
  /// than relying only on the rules rejection.
  static Future<void> endRoom(String roomId) async {
    if (roomId.isEmpty) return;
    await _rooms.doc(roomId).update({'isActive': false});
  }

  /// Persists the designated moderator's uid directly on the room document.
  /// This survives the participant doc being deleted when the moderator
  /// leaves — [RoomParticipantService.join] reads it back and restores the
  /// 'moderator' role when the same user rejoins. Only the host may call
  /// this (firestore.rules' host-update branch covers the write).
  static Future<void> setModerator(String roomId, String moderatorUid) async {
    if (roomId.isEmpty || moderatorUid.isEmpty) return;
    await _rooms.doc(roomId).update({'moderatorUid': moderatorUid});
  }

  /// Clears the stored moderator uid — called when the room no longer has a
  /// designated moderator (e.g. moderator is removed from stage, or host
  /// ends the room after returning). No-op if the field isn't set.
  static Future<void> clearModerator(String roomId) async {
    if (roomId.isEmpty) return;
    await _rooms.doc(roomId).update({'moderatorUid': FieldValue.delete()});
  }

  // ------------------------------------------------------------------
  // Moderator invite sub-collection helpers
  // voiceRooms/{roomId}/moderatorInvites/{inviteeUid}
  // The host writes a doc here; the invitee streams it while inside the
  // room and shows an Accept / Ignore dialog. On Accept the normal
  // RoomParticipantService.promoteToModerator path runs; on Ignore (or
  // after promotion) the doc is deleted. No Cloud Functions required.
  // ------------------------------------------------------------------

  static CollectionReference<Map<String, dynamic>> _invites(String roomId) =>
      _rooms.doc(roomId).collection('moderatorInvites');

  /// Writes (or overwrites) the pending invite for [inviteeUid].
  static Future<void> writeModeratorInvite(String roomId, String inviteeUid) async {
    if (roomId.isEmpty || inviteeUid.isEmpty) return;
    await _invites(roomId).doc(inviteeUid).set({
      'invitedBy': _uid,
      'status': 'pending',
      'invitedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Real-time stream of this user's own moderator invite doc for [roomId].
  /// Emits null whenever the doc does not exist (host hasn't invited yet,
  /// or the invite was already accepted/ignored/deleted).
  static Stream<Map<String, dynamic>?> streamModeratorInvite(
      String roomId, String uid) {
    if (roomId.isEmpty || uid.isEmpty) return Stream.value(null);
    return _invites(roomId)
        .doc(uid)
        .snapshots()
        .map((s) => s.exists ? s.data() : null)
        .handleError((e) {
      debugPrint('VoiceRoomService.streamModeratorInvite error (non-fatal): $e');
      return null;
    });
  }

  /// Deletes the pending invite doc (called on Accept and on Ignore).
  static Future<void> deleteModeratorInvite(String roomId, String uid) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    try {
      await _invites(roomId).doc(uid).delete();
    } catch (e) {
      debugPrint('VoiceRoomService.deleteModeratorInvite error (non-fatal): $e');
    }
  }

  /// Repairs the denormalized hostAvatar on [roomId] if it was stored empty
  /// or outdated. Only the host of the room can update this (governed by firestore.rules).
  static Future<void> repairHostAvatar(String roomId, String avatarUrl) async {
    if (roomId.isEmpty || avatarUrl.isEmpty) return;
    try {
      await _rooms.doc(roomId).update({'hostAvatar': avatarUrl});
    } catch (e) {
      debugPrint('VoiceRoomService.repairHostAvatar non-fatal: $e');
    }
  }

  /// Updates the denormalized `hostName` and `hostAvatar` across all active
  /// rooms hosted by [uid] — called by AuthService.updateProfile when the user
  /// changes their name or avatar.
  static Future<void> updateHostInfoAcrossRooms({
    required String uid,
    required String name,
    required String avatarUrl,
  }) async {
    if (uid.isEmpty) return;
    try {
      final snap = await _rooms
          .where('hostId', isEqualTo: uid)
          .where('isActive', isEqualTo: true)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'hostName': name,
          'hostAvatar': avatarUrl,
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('VoiceRoomService.updateHostInfoAcrossRooms non-fatal: $e');
    }
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
