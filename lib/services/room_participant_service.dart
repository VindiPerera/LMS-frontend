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

  static CollectionReference<Map<String, dynamic>> _participants(String roomId) => FirebaseFirestore
      .instance
      .collection('voiceRooms')
      .doc(roomId)
      .collection('participants');

  static CollectionReference<Map<String, dynamic>> _comments(String roomId) =>
      FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).collection('comments');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Registers the signed-in user as present in [roomId] — the host lands
  /// as an unmuted 'host', everyone else as a muted 'listener'. Called once
  /// from VoiceRoomDetailScreen.initState; pairs with [leave].
  static Future<void> join({required String roomId, required bool isHost}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    if (uid == null || user == null || roomId.isEmpty) return;

    await _participants(roomId).doc(uid).set({
      'uid': uid,
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
    });

    await FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).update({
      'participantCount': FieldValue.increment(1),
    });
  }

  /// Removes the signed-in user's own presence — covers the back button,
  /// closing the tab, or the host ending the room (all tear down
  /// VoiceRoomDetailScreen's State, which calls this from dispose).
  static Future<void> leave(String roomId) async {
    final uid = _uid;
    if (uid == null || roomId.isEmpty) return;
    try {
      await _participants(roomId).doc(uid).delete();
      await FirebaseFirestore.instance.collection('voiceRooms').doc(roomId).update({
        'participantCount': FieldValue.increment(-1),
      });
    } catch (e) {
      // Best-effort: the room doc may already be gone (host just ended it)
      // or the connection may have dropped on the way out — never block
      // the screen from closing over cleanup.
      debugPrint('RoomParticipantService.leave failed (non-fatal): $e');
    }
  }

  /// Live roster, oldest join first. VoiceRoomDetailScreen partitions this
  /// into the speaker grid (host + role == 'speaker') vs. the listener
  /// strip (everyone else) and always pins the host to the first seat,
  /// since re-joining your own room shouldn't bump you out of it.
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
    ).where('role', whereIn: ['host', 'speaker']).get();
    if (seated.docs.length >= speakerSeats) {
      throw Exception('All speaker seats are taken right now.');
    }

    await _participants(roomId).doc(uid).update({'role': 'speaker', 'isMuted': true});
  }

  /// Host-only: moves [uid] back to the audience. firestore.rules also
  /// enforces that only the room's host can do this.
  static Future<void> removeFromStage({required String roomId, required String uid}) async {
    if (roomId.isEmpty || uid.isEmpty) return;
    await _participants(roomId).doc(uid).update({'role': 'listener', 'isMuted': true});
  }

  static Future<void> sendComment({required String roomId, required String text}) async {
    final uid = _uid;
    final user = AuthService.instance.currentUser;
    final trimmed = text.trim();
    if (uid == null || user == null || roomId.isEmpty || trimmed.isEmpty) return;

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
