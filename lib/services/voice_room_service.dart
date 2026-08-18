import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// Live feed of every currently-active room, newest first — the main
  /// Voice tab feed.
  static Stream<List<VoiceRoom>> streamActiveRooms({int limit = 30}) {
    return _rooms
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(VoiceRoom.fromFirestore).toList())
        .handleError((_) => <VoiceRoom>[]);
  }

  /// The room [userId] is currently hosting, or null if they don't have one
  /// active right now. Used by the profile screen's voice-room card and the
  /// Chat tab's "you're hosting" banner — both just need "is this person
  /// live right now", not a query needing a composite index (two equality
  /// filters, no orderBy).
  static Stream<VoiceRoom?> streamActiveRoomForUser(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _rooms
        .where('hostId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
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
  /// if it no longer exists.
  static Future<VoiceRoom?> fetchRoom(String roomId) async {
    if (roomId.isEmpty) return null;
    final doc = await _rooms.doc(roomId).get();
    if (!doc.exists) return null;
    return VoiceRoom.fromFirestore(doc);
  }

  /// Creates a new room hosted by the signed-in user.
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
      participantCount: 1,
      isCreator: true,
    );

    final ref = _rooms.doc();
    await ref.set(draft.toCreateMap());
    final snap = await ref.get();
    return VoiceRoom.fromFirestore(snap);
  }

  /// Ends [roomId] so it stops showing up anywhere. Only the host may do
  /// this (also enforced by firestore.rules) — callers should guard the UI
  /// action on `room.hostId == currentUid` too, rather than relying only on
  /// the rules rejection.
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
