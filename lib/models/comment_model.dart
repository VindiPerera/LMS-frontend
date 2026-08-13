import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A comment (or reply, when [parentCommentId] is set) under a moment.
/// Mirrors `moments/{postId}/comments/{commentId}`.
///
/// Author fields are intentionally flat (`userId`/`userName`/`userAvatar`)
/// rather than a nested [AppUser] like [Moment.user] — a comment row only
/// ever needs a name and an avatar, and keeping the write small matters
/// more here since every comment is a brand-new document.
class CommentModel {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String text;
  final String? parentCommentId;
  final List<String> mentionedUserIds;
  final DateTime? createdAt;

  const CommentModel({
    this.id = '',
    required this.userId,
    required this.userName,
    this.userAvatar = '',
    required this.text,
    this.parentCommentId,
    this.mentionedUserIds = const [],
    this.createdAt,
  });

  bool get isReply => parentCommentId != null && parentCommentId!.isNotEmpty;

  String get timeAgo => createdAt == null ? '' : timeago.format(createdAt!);

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      userName: json['userName']?.toString() ?? 'User',
      userAvatar: json['userAvatar']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      parentCommentId: (json['parentCommentId'] as String?)?.isEmpty ?? true
          ? null
          : json['parentCommentId'] as String,
      mentionedUserIds: (json['mentionedUserIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory CommentModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return CommentModel.fromJson({...?doc.data(), 'id': doc.id});
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'text': text,
      'parentCommentId': parentCommentId,
      'mentionedUserIds': mentionedUserIds,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
