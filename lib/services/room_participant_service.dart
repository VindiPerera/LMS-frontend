import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/room_participant.dart';
import 'auth_service.dart';

/// Firestore access for `voiceRooms/{roomId}/participants/{uid}` and
/// `voiceRooms/{roomId}/comments/{commentId}` — the real per-room roster
/// and comment feed VoiceRoomDetailScreen renders (replacing the old
/// boardSpeakers/boardComments mock data, which was identical on every
/// room). See firestore.rules for the matching subcollection rules.
class RoomParticipantService {
  // Matches the speaker grid's existing 4-per-row layout (host + 7 seats).
  // Seat-claiming isn't done inside a transaction (see requestToSpeak), so
  // the grid itself tolerates a few more than this rather than ever
  // dropping a real participant — this is just the padding target.
  static const speakerSeats = 8;

  // Presence: VoiceRoomDetailScreen pings [heartbeat] on this interval while
  // open; a participant not heard from for [staleAfter] is swept by
  // whichever other client's stream notices first (see
  // sweepStaleParticipants) — nothing server-side is watching, since this
  // project has no deployed Cloud Functions. ~3 missed beats before
  // sweeping tolerates a brief network blip without evicting someone still
  // actually there.
  static const heartbeatInterval = Duration(seconds: 25);
  static const staleAfter = Duration(seconds: 90);

  static CollectionReference<Map<String, dynamic>> _participants(String roomId) => FirebaseFirestore
      .instance
      .collection('voiceRooms')
      .doc(roomId)
      .collection('participants');

  static CollectionReference<Map<String, dynamic>> _comments(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('comments');

  static DocumentReference<Map<String, dynamic>> _room(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId);

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// A fresh, random token VoiceRoomDetailScreen generates once per mount
  /// (`State` field, not `late final` off a stream) and threads through
  /// [join]/[heartbeat]/[leave] as `sessionId`. Firestore's own
  /// auto-generated doc-id randomness is reused here purely as a cheap,
  /// dependency-free unique string — no document is ever created at this
  /// path.
  ///
  /// This exists to fix a real race: back-then-immediately-rejoin (or any
  /// two overlapping mounts for the same room) starts a new [join] before
  /// the old screen's fire-and-forget [leave] has necessarily finished.
  /// Without a fencing token, whichever of that stale leave/fresh join
  /// finishes last "wins" unpredictably — including the stale leave
  /// deleting the doc the fresh join just (re)claimed, silently dropping
  /// the host back to "not present" in the live roster. Every write below
  /// tags or checks `sessionId` so a leave can only ever remove the
  /// session that's actually still current.
  static String newSessionId() => FirebaseFirestore.instance.collection('_').doc().id;

  /// Registers the signed-in user as present in [roomId] — the host lands
  /// as an unmuted 'host', everyone else as a muted 'listener'. Called once
  /// from VoiceRoomDetailScreen.initState; pairs with [leave].
  ///
  /// Idempotent and race-safe: reconnecting to a session that hasn't been
  /// swept as stale yet (e.g. a brief network drop while
  /// VoiceRoomDetailScreen stayed mounted, or navigating back in before the
  /// old doc expired) just refreshes the heartbeat and keeps whatever
  /// role/mute state they had — it does not reset them to a fresh
  /// listener, does not double-increment participantCount, and (via the
  /// transaction below) can't lose to a concurrent stale [leave] the way a
  /// plain read-then-write would.
  static Future<void> join({required String roomId, required bool isHost, required String sessionId}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null || roomId.isEmpty) return;

    final participantRef = _participants(roomId).doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final existing = await tx.get(participantRef);
      if (existing.exists) {
        tx.update(participantRef, {'sessionId': sessionId, 'lastActiveAt': FieldValue.serverTimestamp()});
        return;
      }
      tx.set(participantRef, {
        'uid': uid,
        'sessionId': sessionId,
        'name': user.name,
        'avatarUrl': user.avatarUrl,
        'countryFlag': user.countryFlag,
        'gender': user.gender,
        'age': user.age,
        'nativeLang': user.nativeLang,
        'learningLang': user.learningLang,
        'tags': user.tags,
        'role': isHost ? 'host' : 'listener',
        'isMuted': !isHost,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
      tx.update(_room(roomId), {'participantCount': FieldValue.increment(1)});
    });
  }

  /// Refreshes the signed-in user's presence timestamp — called on
  /// [heartbeatInterval] by VoiceRoomDetailScreen while it's open. No-ops
  /// if [sessionId] no longer matches (a newer join has since claimed this
  /// doc — see [newSessionId]) rather than refreshing presence that isn't
  /// this screen's to refresh. Silent on any failure (offline blip, or the
  /// doc was swept out from under a truly-gone session) — the next tick,
  /// or a fresh [join], is what actually recovers presence, not retrying
  /// this write.
  static Future<void> heartbeat(String roomId, String sessionId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    try {
      final ref = _participants(roomId).doc(uid);
      final snap = await ref.get();
      if (!snap.exists || snap.data()?['sessionId'] != sessionId) return;
      await ref.update({'lastActiveAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('RoomParticipantService.heartbeat failed (non-fatal): $e');
    }
  }

  /// Removes anyone in [participants] whose last heartbeat is older than
  /// [staleAfter] — called from VoiceRoomDetailScreen every time the
  /// participants stream updates, so any client still in the room acts as
  /// a decentralized janitor (no server-side sweep exists). Each removal
  /// is a transaction that re-checks staleness server-side before deleting
  /// (firestore.rules enforces the same check independently), so multiple
  /// clients racing to sweep the same stale entry is harmless — only the
  /// first actually removes anything.
  static Future<void> sweepStaleParticipants(String roomId, List<RoomParticipant> participants) async {
    final now = DateTime.now();
    for (final p in participants) {
      final lastActive = p.lastActiveAt;
      if (lastActive == null || now.difference(lastActive) < staleAfter) continue;
      // ignore: discarded_futures
      _removeStaleParticipant(roomId, p.uid);
    }
  }

  static Future<void> _removeStaleParticipant(String roomId, String staleUid) async {
    final participantRef = _participants(roomId).doc(staleUid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(participantRef);
        if (!snap.exists) return; // already cleaned up by another client
        final lastActive = (snap.data()?['lastActiveAt'] as Timestamp?)?.toDate();
        if (lastActive == null || DateTime.now().difference(lastActive) < staleAfter) {
          return; // they sent a heartbeat since we decided to sweep them
        }
        tx.delete(participantRef);
        tx.update(_room(roomId), {'participantCount': FieldValue.increment(-1)});
      });
    } catch (e) {
      debugPrint('RoomParticipantService: stale sweep of $staleUid failed (non-fatal): $e');
    }
  }

  /// Removes the signed-in user's own presence — covers the back button,
  /// closing the tab, or the host ending the room (all tear down
  /// VoiceRoomDetailScreen's State, which calls this from dispose).
  ///
  /// Only deletes if [sessionId] still matches the doc's current
  /// `sessionId` (set by [join]/[heartbeat]) — if a newer mount already
  /// reclaimed this doc (rejoining faster than this fire-and-forget call
  /// arrives), that's not this session's doc to remove anymore, and doing
  /// so anyway would silently drop the newer session back to "not
  /// present". Transactional so it can't race a concurrent [join] either.
  static Future<void> leave(String roomId, String sessionId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    final participantRef = _participants(roomId).doc(uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(participantRef);
        if (!snap.exists || snap.data()?['sessionId'] != sessionId) return;
        tx.delete(participantRef);
        tx.update(_room(roomId), {'participantCount': FieldValue.increment(-1)});
      });
    } catch (e) {
      // Best-effort: the room doc may already be gone (host just ended it)
      // or the connection may have dropped on the way out — never block
      // the screen from closing over cleanup.
      debugPrint('RoomParticipantService.leave failed (non-fatal): $e');
    }
  }

  /// Live roster, oldest join first. VoiceRoomDetailScreen partitions this
  /// into the speaker grid (anyone RoomParticipant.isSeated — host,
  /// moderator, or speaker) vs. the listener strip (everyone else) and
  /// always pins the host to the first seat, since re-joining your own room
  /// shouldn't bump you out of it.
  static Stream<List<RoomParticipant>> streamParticipants(String roomId) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _participants(roomId)
        .orderBy('joinedAt')
        .snapshots()
        .map((snap) => snap.docs.map((d) => RoomParticipant.fromFirestore(d.id, d.data())).toList())
        .handleError((e) {
          debugPrint('RoomParticipantService.streamParticipants failed (showing no one): $e');
          return <RoomParticipant>[];
        });
  }

  /// Toggles the signed-in user's own mic. Only meaningful once they have a
  /// seat (host/speaker) — callers should steer a listener toward
  /// [requestToSpeak] first rather than calling this.
  static Future<void> setMuted(String roomId, bool muted) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    await _participants(roomId).doc(uid).update({'isMuted': muted});
  }

  /// Claims an open speaker seat for the signed-in listener, muted by
  /// default (matches how a host's room starts too — see [join]). Throws a
  /// plain-text message the UI can show directly once every seat is taken.
  static Future<void> requestToSpeak(String roomId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;

    final seated = await _participants(
      roomId,
    ).where('role', whereIn: ['host', 'moderator', 'speaker']).get();
    if (seated.docs.length >= speakerSeats) {
      throw Exception('All speaker seats are taken right now.');
    }

    await _participants(roomId).doc(uid).update({'role': 'speaker', 'isMuted': true});
  }

  /// Host/moderator-only: moves [uid] back to the audience. firestore.rules
  /// also enforces that only the room's host or a live moderator can do
  /// this.
  static Future<void> removeFromStage({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'role': 'listener', 'isMuted': true});
  }

  /// Host-only: promotes a current stage participant to moderator — see
  /// VoiceRoomDetailScreen's Leave flow, the only place this is called from
  /// (moderator assignment is scoped to "before the host leaves", not a
  /// general anytime action). firestore.rules restricts this write to the
  /// room's host.
  static Future<void> promoteToModerator({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'role': 'moderator'});
  }

  /// Chat is stage-only (host/moderator/speaker) — firestore.rules is the
  /// real enforcement, but checking here first avoids attempting a write
  /// the UI already shouldn't have offered (the composer disables itself
  /// for a non-seated caller).
  static Future<void> sendComment({required String roomId, required String text}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

    final me = await _participants(roomId).doc(uid).get();
    final role = me.data()?['role']?.toString() ?? 'listener';
    if (!['host', 'moderator', 'speaker'].contains(role)) {
      throw Exception('Only stage participants can chat — raise your hand to join the stage.');
    }

    await _comments(roomId).add({
      'senderId': uid,
      'senderName': user.name,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Most recent comment(s) first — the board only ever shows one line
  /// (_CommentLine, same as before), so [limit] stays small.
  static Stream<List<BoardComment>> streamRecentComments(String roomId, {int limit = 1}) {
    if (roomId.isEmpty) return Stream.value(const []);
    return _comments(roomId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (d) => BoardComment(
                  sender: d.data()['senderName']?.toString() ?? 'Someone',
                  text: d.data()['text']?.toString() ?? '',
                ),
              )
              .toList(),
        )
        .handleError((e) {
          debugPrint('RoomParticipantService.streamRecentComments failed (showing none): $e');
          return <BoardComment>[];
        });
  }
}
