import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

enum NotificationType {
  like,
  comment,
  reshare,
  mention;

  String get storageValue => name;

  static NotificationType fromStorage(Object? value) {
    return NotificationType.values.firstWhere(
      (e) => e.storageValue == value,
      orElse: () => NotificationType.like,
    );
  }

  String get verb {
    switch (this) {
      case NotificationType.like:
        return 'liked your moment';
      case NotificationType.comment:
        return 'commented on your moment';
      case NotificationType.reshare:
        return 'reshared your moment';
      case NotificationType.mention:
        return 'mentioned you';
    }
  }
}

/// One entry in `notifications/{uid}/items/{notifId}`. Written by
/// functions/index.js; read-only from the client apart from `isRead`.
class NotificationModel {
  final String id;
  final NotificationType type;
  final String actorId;
  final String actorName;
  final String actorAvatar;
  final String postId;
  final bool isRead;
  final DateTime? createdAt;

  const NotificationModel({
    this.id = '',
    required this.type,
    required this.actorId,
    required this.actorName,
    this.actorAvatar = '',
    required this.postId,
    this.isRead = false,
    this.createdAt,
  });

  String get timeAgo => createdAt == null ? '' : timeago.format(createdAt!);

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? json['notifId']?.toString() ?? '',
      type: NotificationType.fromStorage(json['type']),
      actorId: json['actorId']?.toString() ?? '',
      actorName: json['actorName']?.toString() ?? 'Someone',
      actorAvatar: json['actorAvatar']?.toString() ?? '',
      postId: json['postId']?.toString() ?? '',
      isRead: json['isRead'] == true,
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory NotificationModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return NotificationModel.fromJson({...?doc.data(), 'id': doc.id});
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.storageValue,
      'actorId': actorId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'postId': postId,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
