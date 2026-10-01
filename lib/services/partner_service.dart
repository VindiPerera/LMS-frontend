import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import '../utils/presence.dart';
import '../utils/stream_fallback.dart';

/// Fetches language-exchange partners for the Connect tab from the
/// `users` Firestore collection (see connect_screen.dart).
class PartnerService {
  static final _users = FirebaseFirestore.instance.collection('users');

  /// Other users, online first then newest first. Requires a composite
  /// index on (isOnline desc, createdAt desc) — see firestore.indexes.json;
  /// Firestore will also print a direct console link to create it the first
  /// time this query runs without one.
  static Future<List<AppUser>> fetchPartners({int limit = 30}) async {
    final selfUid = FirebaseAuth.instance.currentUser?.uid;

    final snapshot = await _users
        .orderBy('isOnline', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .where((doc) => doc.id != selfUid)
        .map((doc) => AppUser.fromJson({...doc.data(), 'id': doc.id}))
        .toList();
  }

  /// A single partner's full profile, for partner_profile_screen.dart.
  static Future<AppUser> fetchPartner(String id) async {
    final doc = await _users.doc(id).get();
    if (!doc.exists) {
      throw StateError('This user no longer exists.');
    }
    return AppUser.fromJson({...doc.data()!, 'id': doc.id});
  }

  /// Live online/offline status for one user — used anywhere a green
  /// indicator needs to actually stay current while it's on screen (e.g.
  /// chat_detail_screen.dart's header) rather than showing whatever was
  /// true at the moment that screen happened to open. Backed by
  /// AuthService.setOnlineStatus/main_shell.dart's app-lifecycle observer,
  /// which keep `users/{uid}.isOnline` current on the other end.
  static Stream<bool> streamIsOnline(String uid) {
    if (uid.isEmpty) return Stream.value(false);
    return _users
        .doc(uid)
        .snapshots()
        .map((doc) {
          final lastSeenAt = doc.data()?['lastSeenAt'];
          return isActuallyOnline(
            doc.data()?['isOnline'] == true,
            lastSeenAt is Timestamp ? lastSeenAt : null,
          );
        })
        .withFallback(() => false);
  }

  /// Live `users/{uid}.activeRoomId` — non-empty exactly while [uid] has a
  /// live participant doc in that voice room (see
  /// RoomParticipantService.join/leave). Drives the "in a voice room" badge
  /// in chat_list_screen.dart and the "Go Look" banner in
  /// chat_detail_screen.dart. Null (not '') once they're not in one, so a
  /// caller can tell "definitely not in a room" apart from "still loading"
  /// via a plain `snapshot.hasData` check if it needs to.
  static Stream<String?> streamActiveRoomId(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _users
        .doc(uid)
        .snapshots()
        .map((doc) {
          final id = doc.data()?['activeRoomId']?.toString() ?? '';
          return id.isEmpty ? null : id;
        })
        .withFallback(() => null);
  }
}
