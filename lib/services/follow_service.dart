import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import 'auth_service.dart';

/// The "Follow" relationship shown on partner_profile_screen.dart and the
/// Following/Followers counts on me_screen.dart — previously both were
/// purely decorative (a local `bool _isFollowing` that reset on navigation,
/// and hardcoded '1'/'1' stat text). Backed by two mirrored Firestore
/// subcollections, same shape as chats' `participantInfo` (a denormalized
/// snapshot alongside each edge) so a Following/Followers list can render
/// without an extra read per row:
///
///   users/{uid}/following/{targetUid}  — {name, handle, avatarUrl,
///     countryFlag, followedAt}, exists iff uid follows targetUid.
///   users/{uid}/followers/{followerUid} — the mirror image, written under
///     the person being followed.
///
/// Both sides of a follow/unfollow are written together in one batch so
/// they can't drift out of sync with each other.
class FollowService {
  static final _users = FirebaseFirestore.instance.collection('users');

  static String? _uid() => FirebaseAuth.instance.currentUser?.uid;

  static Map<String, dynamic> _snapshotOf(AppUser user) {
    return {
      'name': user.name,
      'handle': user.handle,
      'avatarUrl': user.avatarUrl,
      'countryFlag': user.countryFlag,
      'followedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Follows [target]. No-ops if not signed in, already following, or
  /// [target] is the signed-in user themself (can't follow yourself).
  static Future<void> follow(AppUser target) async {
    final uid = _uid();
    final me = AuthService.instance.currentUser;
    if (uid == null || me == null || target.id.isEmpty || target.id == uid) {
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    batch.set(
      _users.doc(uid).collection('following').doc(target.id),
      _snapshotOf(target),
    );
    batch.set(
      _users.doc(target.id).collection('followers').doc(uid),
      _snapshotOf(me),
    );
    await batch.commit();
  }

  static Future<void> unfollow(String targetId) async {
    final uid = _uid();
    if (uid == null || targetId.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_users.doc(uid).collection('following').doc(targetId));
    batch.delete(_users.doc(targetId).collection('followers').doc(uid));
    await batch.commit();
  }

  /// Whether the signed-in user currently follows [targetId] — live, for
  /// partner_profile_screen.dart's Follow button.
  static Stream<bool> streamIsFollowing(String targetId) {
    final uid = _uid();
    if (uid == null || targetId.isEmpty) return Stream.value(false);
    return _users
        .doc(uid)
        .collection('following')
        .doc(targetId)
        .snapshots()
        .map((doc) => doc.exists)
        .handleError((_) => false);
  }

  /// Live counts for me_screen.dart / partner_profile_screen.dart's stats
  /// row. A plain doc-count listener rather than a maintained counter field
  /// — same tradeoff me_screen.dart already makes for "My Moments" (see
  /// MomentService.streamUserMoments there): simpler and can't drift out of
  /// sync, at the cost of re-reading the whole subcollection per update
  /// (fine at this app's scale).
  static Stream<int> streamFollowingCount(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return _users
        .doc(uid)
        .collection('following')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((_) => 0);
  }

  static Stream<int> streamFollowersCount(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    return _users
        .doc(uid)
        .collection('followers')
        .snapshots()
        .map((snap) => snap.docs.length)
        .handleError((_) => 0);
  }

  /// Live list for follow_list_screen.dart.
  static Stream<List<AppUser>> streamFollowing(String uid) => _streamEdges(uid, 'following');

  static Stream<List<AppUser>> streamFollowers(String uid) => _streamEdges(uid, 'followers');

  static Stream<List<AppUser>> _streamEdges(String uid, String subcollection) {
    if (uid.isEmpty) return Stream.value(const []);
    return _users
        .doc(uid)
        .collection(subcollection)
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => AppUser.fromJson({...doc.data(), 'id': doc.id}))
              .toList(),
        )
        .handleError((_) => <AppUser>[]);
  }
}
