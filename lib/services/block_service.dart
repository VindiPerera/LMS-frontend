import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'follow_service.dart';

/// "Block User" (partner_profile_screen.dart's "⋮" menu) — the first real
/// writer of the `friendships/{docId}.status == 'blocked'` state that
/// firestore.rules' `isBlockedBy()` has enforced against (hiding a blocked
/// pair's moments from each other) since before this feature actually
/// existed anywhere in the app. Reuses that same `friendships` collection
/// and its already-deployed rules (`allow read, write` for either
/// participant) rather than a new one — no rules change needed for this.
///
/// Scope: hides each other's moments from the feed (already enforced
/// server-side) and unfollows in both directions. Doesn't additionally
/// block messaging or profile viewing — not asked for, and would need its
/// own separate rules work in the `chats`/`users` collections.
class BlockService {
  BlockService._();

  static final _friendships = FirebaseFirestore.instance.collection('friendships');

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Matches firestore.rules' own `friendshipId()` exactly — the doc id is
  /// never computed any other way anywhere in the app.
  static String _docId(String uidA, String uidB) {
    final ids = [uidA, uidB]..sort();
    return ids.join('_');
  }

  static Future<void> blockUser(String targetUid) async {
    final uid = _uid;
    if (uid == null || targetUid.isEmpty || targetUid == uid) return;

    await _friendships.doc(_docId(uid, targetUid)).set({
      'userIds': [uid, targetUid],
      'status': 'blocked',
      'blockedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Best-effort, not load-bearing for the block itself — blocking someone
    // you don't follow (or who doesn't follow you) is a no-op either way.
    try {
      await FollowService.unfollow(targetUid);
    } catch (_) {}
  }

  /// Un-blocking removes the doc outright rather than flipping `status`
  /// back to something else — there's no "friends"/"pending" state for this
  /// pair to revert to (see firestore.rules' doc comment on why the old
  /// friend-request states never get written anymore), so nothing else
  /// would ever read this doc again once it's not 'blocked'.
  static Future<void> unblockUser(String targetUid) async {
    final uid = _uid;
    if (uid == null || targetUid.isEmpty) return;
    await _friendships.doc(_docId(uid, targetUid)).delete();
  }

  /// Live — partner_profile_screen.dart's "⋮" menu switches between "Block
  /// User" and "Unblock User" based on this.
  static Stream<bool> streamIsBlocked(String targetUid) {
    final uid = _uid;
    if (uid == null || targetUid.isEmpty) return Stream.value(false);
    return _friendships
        .doc(_docId(uid, targetUid))
        .snapshots()
        .map((doc) => doc.data()?['status'] == 'blocked')
        .handleError((_) => false);
  }

  /// Uids the signed-in user has blocked — me_screen.dart's "Blocked Users"
  /// list. The `userIds arrayContains` filter mirrors firestore.rules'
  /// `request.auth.uid in resource.data.userIds` check exactly, same as
  /// every other arrayContains-filtered list query in this app (see
  /// MomentService._audienceKeysForReader's doc comment) — Firestore
  /// rejects the whole query outright if the filter doesn't line up with
  /// the rule. `blockedBy == uid` is then filtered client-side (not a rule
  /// concern) to show only pairs *this* user blocked, not ones where they
  /// were the one blocked.
  static Stream<List<String>> streamBlockedUserIds() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _friendships
        .where('userIds', arrayContains: uid)
        .where('status', isEqualTo: 'blocked')
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d.data()['blockedBy'] == uid)
            .map((d) => (d.data()['userIds'] as List).map((e) => e.toString()).firstWhere((id) => id != uid, orElse: () => ''))
            .where((id) => id.isNotEmpty)
            .toList())
        .handleError((_) => <String>[]);
  }
}
