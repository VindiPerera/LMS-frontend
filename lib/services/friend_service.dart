import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user.dart';
import 'partner_service.dart';

enum FriendStatus { none, pending, incoming, friends, blocked }

class FriendService {
  FriendService._();
  static final instance = FriendService._();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _currentUid => _auth.currentUser?.uid;

  /// Deterministic document ID for 1:1 friendships
  String getFriendshipDocId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  /// Send a friend request using Firestore batch write
  Future<void> sendFriendRequest(String toUserId) async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final docId = getFriendshipDocId(uid, toUserId);
    final batch = _firestore.batch();

    // 1. Write friendship document
    batch.set(
      _firestore.collection('friendships').doc(docId),
      {
        'userIds': [uid, toUserId],
        'status': 'pending',
        'requesterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    // 2. Add to target user's friend_requests subcollection
    batch.set(
      _firestore
          .collection('users')
          .doc(toUserId)
          .collection('friend_requests')
          .doc(docId),
      {
        'fromUserId': uid,
        'toUserId': toUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
  }

  /// Accept incoming friend request using batch write
  Future<void> acceptRequest(String fromUserId) async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final docId = getFriendshipDocId(uid, fromUserId);
    final batch = _firestore.batch();

    batch.update(
      _firestore.collection('friendships').doc(docId),
      {
        'status': 'friends',
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );

    batch.update(
      _firestore
          .collection('users')
          .doc(uid)
          .collection('friend_requests')
          .doc(docId),
      {
        'status': 'accepted',
      },
    );

    await batch.commit();
  }

  /// Decline incoming friend request
  Future<void> declineRequest(String fromUserId) async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final docId = getFriendshipDocId(uid, fromUserId);
    final batch = _firestore.batch();

    batch.delete(_firestore.collection('friendships').doc(docId));
    batch.delete(
      _firestore
          .collection('users')
          .doc(uid)
          .collection('friend_requests')
          .doc(docId),
    );

    await batch.commit();
  }

  /// Cancel outgoing request
  Future<void> cancelRequest(String toUserId) async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final docId = getFriendshipDocId(uid, toUserId);
    final batch = _firestore.batch();

    batch.delete(_firestore.collection('friendships').doc(docId));
    batch.delete(
      _firestore
          .collection('users')
          .doc(toUserId)
          .collection('friend_requests')
          .doc(docId),
    );

    await batch.commit();
  }

  /// Unfriend an existing friend
  Future<void> unfriend(String friendId) async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return;

    final docId = getFriendshipDocId(uid, friendId);
    await _firestore.collection('friendships').doc(docId).delete();
  }

  /// Stream friendship status for a given friendId
  Stream<FriendStatus> streamFriendshipStatus(String friendId) {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(FriendStatus.none);
    }

    final docId = getFriendshipDocId(uid, friendId);
    return _firestore
        .collection('friendships')
        .doc(docId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) {
        return FriendStatus.none;
      }
      final data = snap.data()!;
      final status = data['status']?.toString() ?? 'none';
      final requesterId = data['requesterId']?.toString() ?? '';

      if (status == 'friends') {
        return FriendStatus.friends;
      } else if (status == 'blocked') {
        return FriendStatus.blocked;
      } else if (status == 'pending') {
        if (requesterId == uid) {
          return FriendStatus.pending;
        } else {
          return FriendStatus.incoming;
        }
      }
      return FriendStatus.none;
    });
  }

  /// Fetch a friend's real profile from `users/{friendId}`. Reuses
  /// PartnerService (already backing the Connect tab) instead of duplicating
  /// the fetch — and, importantly, does NOT invent a placeholder profile
  /// when the doc is missing or the request fails. A scanned/shared QR code
  /// can point at an id that no longer exists (deleted account, corrupted
  /// code, someone else's app); silently showing a fabricated "User xyz123"
  /// profile would let a friend request go out to nobody. Callers must
  /// handle the thrown StateError/FirebaseException and show a real error.
  Future<AppUser> getFriendProfile(String friendId) {
    return PartnerService.fetchPartner(friendId);
  }

  /// The other participant's uid in a two-person `friendships` doc, or ''
  /// if [doc]'s `userIds` doesn't actually contain [uid] (shouldn't happen,
  /// but keeps the map/where below from throwing on bad data).
  String _otherParticipant(Map<String, dynamic> doc, String uid) {
    final ids = (doc['userIds'] as List?)?.map((e) => e.toString()) ?? const [];
    return ids.firstWhere((id) => id != uid, orElse: () => '');
  }

  /// uids of everyone with an active `friends` friendship with the current
  /// user. Used by MomentsScreen to resolve `visibility: "friends"` posts
  /// client-side (Firestore can't express that OR across a joined
  /// collection in a single query).
  Stream<Set<String>> streamFriendIds() {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return Stream.value(const <String>{});
    return _firestore
        .collection('friendships')
        .where('userIds', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d.data()['status'] == 'friends')
            .map((d) => _otherParticipant(d.data(), uid))
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  /// uids the current user is in a `blocked` friendship with (either
  /// direction — this schema doesn't track who blocked whom, just that the
  /// pair shouldn't see each other). Used to filter the Moments feed.
  Stream<Set<String>> streamBlockedIds() {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) return Stream.value(const <String>{});
    return _firestore
        .collection('friendships')
        .where('userIds', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d.data()['status'] == 'blocked')
            .map((d) => _otherParticipant(d.data(), uid))
            .where((id) => id.isNotEmpty)
            .toSet());
  }
}
