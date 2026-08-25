import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The thumbs-up "like" button on partner_profile_screen.dart — previously
/// a purely local `bool _isLiked` / `int _likesCount = 1` that reset to the
/// same fake "1" every time the screen reopened and was invisible to
/// everyone else. Backed by one Firestore subcollection, same shape as
/// FollowService:
///
///   users/{uid}/profileLikes/{likerUid} — exists iff likerUid has liked
///     uid's profile.
class ProfileLikeService {
  static final _users = FirebaseFirestore.instance.collection('users');

  static String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  static Future<void> like(String targetUid) async {
    final uid = _uid();
    if (uid == null || targetUid.isEmpty || targetUid == uid) return;
    await _users
        .doc(targetUid)
        .collection('profileLikes')
        .doc(uid)
        .set({'likedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> unlike(String targetUid) async {
    final uid = _uid();
    if (uid == null || targetUid.isEmpty) return;
    await _users.doc(targetUid).collection('profileLikes').doc(uid).delete();
  }

  /// Whether the signed-in user has liked [targetUid]'s profile — live, so
  /// it reflects reality (e.g. after unliking on another device) instead of
  /// a value that's only ever right at the moment the screen opened.
  static Stream<bool> streamIsLiked(String targetUid) {
    final uid = _uid();
    if (uid == null || targetUid.isEmpty) return Stream.value(false);
    return _users
        .doc(targetUid)
        .collection('profileLikes')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((_) => false);
  }

  /// Total like count for [uid]'s profile. A plain doc-count listener,
  /// same tradeoff FollowService's counts make (see its doc comment).
  static Stream<int> streamLikeCount(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return _users
        .doc(uid)
        .collection('profileLikes')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((_) => 0);
  }
}
