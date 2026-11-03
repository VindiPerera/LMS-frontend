import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// `users/{uid}/visitors/{visitorUid}` — who has viewed a profile. Private
/// to the profile owner (see firestore.rules), unlike followers/following.
/// One doc per visitor (upserted, not appended), so repeat visits bump
/// `visitedAt` rather than inflating the count — matches how
/// FollowService.streamFollowersCount already treats "count = docs in the
/// subcollection" for the same reason (simple, can't drift).
class VisitorService {
  VisitorService._();

  static final _users = FirebaseFirestore.instance.collection('users');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Records the signed-in user viewing [targetUid]'s profile. No-op for a
  /// signed-out viewer or a self-visit (opening your own profile never
  /// counts as a "visitor").
  static Future<void> recordVisit(String targetUid) async {
    final uid = _uid;
    if (uid == null || targetUid.isEmpty || targetUid == uid) return;
    try {
      await _users.doc(targetUid).collection('visitors').doc(uid).set({
        'visitedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort — a failed visit log should never block opening a
      // profile.
    }
  }

  /// Live visitor count for me_screen.dart's "Visitors" stat card.
  static Stream<int> streamVisitorCount(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return _users
        .doc(uid)
        .collection('visitors')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((_) => 0);
  }
}
