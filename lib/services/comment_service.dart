import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/comment_model.dart';
import 'auth_service.dart';

/// All Firestore access for `moments/{postId}/comments`. `commentCount` on
/// the parent post is never touched here — functions/index.js's
/// onCommentCreate/onCommentDelete own that counter.
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
  /// `@handle` mentions inside [text] are resolved to uids and stored on
  /// the comment so functions/index.js's onCommentCreate can push to them.
  static Future<void> addComment({
    required String postId,
    required String text,
    String? parentCommentId,
  }) async {
    if (postId.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final currentUser = AuthService.instance.currentUser;
    final cleanText = text.trim();
    if (uid == null || currentUser == null || cleanText.isEmpty) return;

    final mentionedUserIds = await _resolveMentions(cleanText);

    final comment = CommentModel(
      userId: uid,
      userName: currentUser.name,
      userAvatar: currentUser.avatarUrl,
      text: cleanText,
      parentCommentId: parentCommentId,
      mentionedUserIds: mentionedUserIds,
    );

    await _comments(postId).add(comment.toMap());
  }

  static Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    if (postId.isEmpty || commentId.isEmpty) return;
    await _comments(postId).doc(commentId).delete();
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
