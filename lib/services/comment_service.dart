import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/comment_model.dart';
import 'auth_service.dart';
import 'notification_api_service.dart';

/// All Firestore access for `moments/{postId}/comments`. `commentCount` on
/// the parent post is maintained client-side here via FieldValue.increment
/// (this project doesn't deploy Cloud Functions — no Blaze plan — so there's
/// no server-side counter owner; the same pattern likeCount already used is
/// applied here and to reshareCount in moment_service.dart's createMoment).
class CommentService {
  static final RegExp _mentionPattern = RegExp(r'@([a-zA-Z0-9_]{2,30})');

  static CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      FirebaseFirestore.instance
          .collection('moments')
          .doc(postId)
          .collection('comments');

  /// Top-level comments (no parent), oldest first. See
  /// firestore.indexes.json index #3.
  static Stream<List<CommentModel>> streamTopLevelComments(String postId) {
    if (postId.isEmpty) return const Stream<List<CommentModel>>.empty();
    return _comments(postId)
        .where('parentCommentId', isNull: true)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(CommentModel.fromFirestore).toList());
  }

  /// Replies to a single top-level comment, oldest first.
  static Stream<List<CommentModel>> streamReplies(
    String postId,
    String parentCommentId,
  ) {
    if (postId.isEmpty || parentCommentId.isEmpty) {
      return const Stream<List<CommentModel>>.empty();
    }
    return _comments(postId)
        .where('parentCommentId', isEqualTo: parentCommentId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(CommentModel.fromFirestore).toList());
  }

  /// Posts a comment (or, when [parentCommentId] is set, a reply).
  /// `@handle` mentions inside [text] are resolved to uids, stored on the
  /// comment for comment_sheet.dart's tappable-mention rendering, and also
  /// pushed to (along with the post owner) via NotificationApiService —
  /// see that class's doc comment for why this goes through hello-backend
  /// rather than a Cloud Function.
  static Future<void> addComment({
    required String postId,
    required String text,
    String? parentCommentId,
  }) async {
    if (postId.isEmpty) return;
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final cleanText = text.trim();
    if (firebaseUser == null || cleanText.isEmpty) {
      throw StateError('You must be signed in to post a comment.');
    }
    final uid = firebaseUser.uid;


    var currentUser = AuthService.instance.currentUser;
    currentUser ??= await AuthService.instance.refreshCurrentUser();

    final userDisplayName = firebaseUser.displayName;
    final userEmail = firebaseUser.email;
    final userPhoto = firebaseUser.photoURL;

    final userName = (currentUser != null && currentUser.name.isNotEmpty)
        ? currentUser.name
        : (userDisplayName != null && userDisplayName.isNotEmpty)
            ? userDisplayName
            : (userEmail != null && userEmail.isNotEmpty)
                ? userEmail.split('@').first
                : 'User';
    final userAvatar = currentUser?.avatarUrl ?? userPhoto ?? '';


    final mentionedUserIds = await _resolveMentions(cleanText);

    final comment = CommentModel(
      userId: uid,
      userName: userName,
      userAvatar: userAvatar,
      text: cleanText,
      parentCommentId: parentCommentId,
      mentionedUserIds: mentionedUserIds,
    );

    final batch = FirebaseFirestore.instance.batch();
    final newCommentRef = _comments(postId).doc();
    batch.set(newCommentRef, comment.toMap());

    final postRef = FirebaseFirestore.instance.collection('moments').doc(postId);
    batch.update(postRef, {
      'commentCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Fire-and-forget: notify the post owner (if it's not their own
    // comment) and anyone @mentioned. One extra read for the owner's id —
    // acceptable here, this isn't a hot path like the feed/scroll.
    unawaited(_notifyAfterComment(
      postRef: postRef,
      commenterId: uid,
      commenterName: userName,
      text: cleanText,
      mentionedUserIds: mentionedUserIds,
    ));
  }

  static Future<void> _notifyAfterComment({
    required DocumentReference<Map<String, dynamic>> postRef,
    required String commenterId,
    required String commenterName,
    required String text,
    required List<String> mentionedUserIds,
  }) async {
    String? ownerId;
    try {
      final postSnap = await postRef.get();
      ownerId = (postSnap.data()?['user'] as Map?)?['id']?.toString();
    } catch (_) {
      return; // Can't notify anyone without knowing the owner — bail quietly.
    }

    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    final alreadyNotified = <String>{};

    if (ownerId != null && ownerId.isNotEmpty && ownerId != commenterId) {
      alreadyNotified.add(ownerId);
      // ignore: discarded_futures
      NotificationApiService.sendPush(
        recipientUid: ownerId,
        title: commenterName,
        body: 'commented: $preview',
        data: {'type': 'comment', 'postId': postRef.id, 'actorId': commenterId},
      );
    }

    for (final mentionedUid in mentionedUserIds) {
      if (mentionedUid == commenterId || !alreadyNotified.add(mentionedUid)) continue;
      // ignore: discarded_futures
      NotificationApiService.sendPush(
        recipientUid: mentionedUid,
        title: commenterName,
        body: 'mentioned you: $preview',
        data: {'type': 'mention', 'postId': postRef.id, 'actorId': commenterId},
      );
    }
  }

  static Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    if (postId.isEmpty || commentId.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    final commentRef = _comments(postId).doc(commentId);
    batch.delete(commentRef);

    final postRef = FirebaseFirestore.instance.collection('moments').doc(postId);
    batch.update(postRef, {
      'commentCount': FieldValue.increment(-1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Prefix search over `users.handle`, for the "@username" typeahead in
  /// comment_sheet.dart. Empty/too-short prefixes return nothing rather
  /// than the whole users collection.
  static Future<List<Map<String, String>>> searchUsersByHandle(
    String prefix,
  ) async {
    final clean = prefix.trim().toLowerCase();
    if (clean.isEmpty) return const [];

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .orderBy('handle')
        .startAt([clean])
        .endAt(['$clean'])
        .limit(8)
        .get();

    return snap.docs
        .map((d) => {
              'id': d.id,
              'handle': d.data()['handle']?.toString() ?? '',
              'name': d.data()['name']?.toString() ?? '',
              'avatarUrl': d.data()['avatarUrl']?.toString() ?? '',
            })
        .toList();
  }

  /// Exact handle -> uid lookup, for tapping an "@handle" mention inside a
  /// posted comment (comment_sheet.dart's `_MentionText`).
  static Future<String?> findUserIdByHandle(String handle) async {
    final clean = handle.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('handle', isEqualTo: clean)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }

  static Future<List<String>> _resolveMentions(String text) async {
    final handles = _mentionPattern
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
    if (handles.isEmpty) return const [];

    // whereIn caps at 30 values (10 on older SDKs) — comments realistically
    // never mention more than a handful of people, so a single chunk is fine.
    final chunk = handles.take(30).toList();
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('handle', whereIn: chunk)
        .get();

    return snap.docs.map((d) => d.id).toList();
  }
}
