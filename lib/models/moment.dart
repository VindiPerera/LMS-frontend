import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../config/api_config.dart';
import 'user.dart';


/// What kind of media (if any) a moment carries. Drives which layout
/// [PostImageGrid]/[MomentCard] picks.
enum MomentMediaType {
  none,
  image,
  video;

  String get storageValue => name;

  static MomentMediaType fromStorage(Object? value) {
    return MomentMediaType.values.firstWhere(
      (e) => e.storageValue == value,
      orElse: () => MomentMediaType.none,
    );
  }
}

/// Who can see a moment. Enforced both client-side (feed filtering) and in
/// firestore.rules.
enum MomentVisibility {
  public,
  friends,
  onlyMe;

  String get storageValue => name;

  static MomentVisibility fromStorage(Object? value) {
    return MomentVisibility.values.firstWhere(
      (e) => e.storageValue == value,
      orElse: () => MomentVisibility.public,
    );
  }
}

/// A single post in the Moments feed — mirrors the `moments/{postId}`
/// Firestore document. The author is kept as a denormalized [AppUser]
/// snapshot (`user`) rather than flat `userId`/`userName`/`userAvatar`
/// fields, matching how the rest of the app (AppAvatar, FriendProfileScreen,
/// language badges) already expects to consume author data.
class Moment {
  final String id;
  final AppUser user;
  final String text;
  final List<String> imageUrls;
  final String? videoUrl;
  final String? videoThumbnailUrl;
  final MomentMediaType mediaType;

  /// Plain like (uids). A reaction other than the default heart also adds
  /// the uid here, so `likeCount`/`isLikedBy` stay meaningful regardless of
  /// which emoji was picked.
  final List<String> likes;

  /// emoji -> uids who picked it, e.g. {"❤️": ["uid1"], "😂": ["uid2"]}.
  final Map<String, List<String>> reactions;

  final int likeCount;
  final int commentCount;
  final int reshareCount;
  final int reportCount;
  final MomentVisibility visibility;
  final bool isReshare;
  final String? originalPostId;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Moment({
    this.id = '',
    required this.user,
    this.text = '',
    this.imageUrls = const [],
    this.videoUrl,
    this.videoThumbnailUrl,
    this.mediaType = MomentMediaType.none,
    this.likes = const [],
    this.reactions = const {},
    this.likeCount = 0,
    this.commentCount = 0,
    this.reshareCount = 0,
    this.reportCount = 0,
    this.visibility = MomentVisibility.public,
    this.isReshare = false,
    this.originalPostId,
    this.isDeleted = false,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasMedia => mediaType != MomentMediaType.none;

  bool isLikedBy(String uid) => uid.isNotEmpty && likes.contains(uid);

  /// The reaction emoji [uid] picked, or null if they only plain-liked (or
  /// haven't reacted at all).
  String? reactionOf(String uid) {
    for (final entry in reactions.entries) {
      if (entry.value.contains(uid)) return entry.key;
    }
    return null;
  }

  /// Up to 2 most-used reaction emojis, for the "❤️😂 24" summary next to
  /// the like count. Falls back to the default heart when nobody has picked
  /// a specific emoji yet but the post still has plain likes.
  List<String> get topReactionEmojis {
    final entries = reactions.entries.where((e) => e.value.isNotEmpty).toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    if (entries.isEmpty) {
      return likeCount > 0 ? const ['❤️'] : const [];
    }
    return entries.take(2).map((e) => e.key).toList();
  }

  String get timeAgo => createdAt == null ? '' : timeago.format(createdAt!);

  /// Decodes a `moments/{postId}` Firestore document. Callers must merge the
  /// document id into the map first (as `'id'`).
  factory Moment.fromJson(Map<String, dynamic> json) {
    final userMap = json['user'] as Map<String, dynamic>? ?? const {};
    final likesList = _asStringList(json['likes']);
    final parsedLikeCount = _asInt(json['likeCount']);
    final effectiveLikeCount = parsedLikeCount > 0 ? parsedLikeCount : likesList.length;

    return Moment(
      id: json['id']?.toString() ?? '',
      user: AppUser.fromJson({...userMap, 'id': userMap['id'] ?? json['userId']}),
      text: json['text']?.toString() ?? '',
      imageUrls: _asStringList(json['imageUrls']).map(ApiConfig.resolveUrl).toList(),
      videoUrl: json['videoUrl'] != null ? ApiConfig.resolveUrl(json['videoUrl'].toString()) : null,
      videoThumbnailUrl: json['videoThumbnailUrl'] != null
          ? ApiConfig.resolveUrl(json['videoThumbnailUrl'].toString())
          : null,

      mediaType: MomentMediaType.fromStorage(json['mediaType']),
      likes: likesList,
      reactions: _asReactionsMap(json['reactions']),
      likeCount: effectiveLikeCount,
      commentCount: _asInt(json['commentCount']),
      reshareCount: _asInt(json['reshareCount']),
      reportCount: _asInt(json['reportCount']),
      visibility: MomentVisibility.fromStorage(json['visibility']),
      isReshare: json['isReshare'] == true,
      originalPostId: json['originalPostId']?.toString(),
      isDeleted: json['isDeleted'] == true,
      createdAt: _asDateTime(json['createdAt']),
      updatedAt: _asDateTime(json['updatedAt']),
    );
  }

  factory Moment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Moment.fromJson({...?doc.data(), 'id': doc.id});
  }

  /// Fields safe to hand to `.set()`/`.add()` on create. `id`, `createdAt`
  /// and counters that are Cloud-Function-only are intentionally excluded
  /// here — see [MomentService.createMoment].
  Map<String, dynamic> toCreateMap() {
    return {
      'user': {
        'id': user.id,
        'name': user.name,
        'handle': user.handle,
        'avatarUrl': user.avatarUrl,
        'countryFlag': user.countryFlag,
        'nativeLang': user.nativeLang,
        'learningLang': user.learningLang,
      },
      'text': text,
      'imageUrls': imageUrls,
      if (videoUrl != null) 'videoUrl': videoUrl,
      if (videoThumbnailUrl != null) 'videoThumbnailUrl': videoThumbnailUrl,
      'mediaType': mediaType.storageValue,
      'likes': <String>[],
      'reactions': <String, List<String>>{},
      'likeCount': 0,
      'commentCount': 0,
      'reshareCount': 0,
      'reportCount': 0,
      'visibility': visibility.storageValue,
      'isReshare': isReshare,
      if (originalPostId != null) 'originalPostId': originalPostId,
      'isDeleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Full map, used by tests and anywhere a plain (non-server-timestamp)
  /// snapshot of the document is useful.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': user.id,
      'user': {
        'id': user.id,
        'name': user.name,
        'handle': user.handle,
        'avatarUrl': user.avatarUrl,
        'countryFlag': user.countryFlag,
        'nativeLang': user.nativeLang,
        'learningLang': user.learningLang,
      },
      'text': text,
      'imageUrls': imageUrls,
      'videoUrl': videoUrl,
      'videoThumbnailUrl': videoThumbnailUrl,
      'mediaType': mediaType.storageValue,
      'likes': likes,
      'reactions': reactions,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'reshareCount': reshareCount,
      'reportCount': reportCount,
      'visibility': visibility.storageValue,
      'isReshare': isReshare,
      'originalPostId': originalPostId,
      'isDeleted': isDeleted,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  Moment copyWith({
    String? id,
    AppUser? user,
    String? text,
    List<String>? imageUrls,
    String? videoUrl,
    String? videoThumbnailUrl,
    MomentMediaType? mediaType,
    List<String>? likes,
    Map<String, List<String>>? reactions,
    int? likeCount,
    int? commentCount,
    int? reshareCount,
    int? reportCount,
    MomentVisibility? visibility,
    bool? isReshare,
    String? originalPostId,
    bool? isDeleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Moment(
      id: id ?? this.id,
      user: user ?? this.user,
      text: text ?? this.text,
      imageUrls: imageUrls ?? this.imageUrls,
      videoUrl: videoUrl ?? this.videoUrl,
      videoThumbnailUrl: videoThumbnailUrl ?? this.videoThumbnailUrl,
      mediaType: mediaType ?? this.mediaType,
      likes: likes ?? this.likes,
      reactions: reactions ?? this.reactions,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      reshareCount: reshareCount ?? this.reshareCount,
      reportCount: reportCount ?? this.reportCount,
      visibility: visibility ?? this.visibility,
      isReshare: isReshare ?? this.isReshare,
      originalPostId: originalPostId ?? this.originalPostId,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<String> _asStringList(Object? value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  static Map<String, List<String>> _asReactionsMap(Object? value) {
    if (value is Map) {
      return value.map(
        (key, v) => MapEntry(
          key.toString(),
          v is List ? v.map((e) => e.toString()).toList() : <String>[],
        ),
      );
    }
    return const {};
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
