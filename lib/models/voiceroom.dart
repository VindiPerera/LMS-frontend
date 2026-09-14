import 'package:cloud_firestore/cloud_firestore.dart';

class VoiceRoom {
  final String id;
  final String hostId;
  final String title;
  final String hostName;
  final String hostAvatar;
  final String hostFlag;
  final String category;
  final String tag;
  final String coverGradientSeed;
  final List<String> participantAvatars;
  final int participantCount;
  final bool isTop;
  final bool isCreator;
  final bool isActive;
  // Denormalized read/join allow-list, mirroring MomentService's `audience`
  // pattern (see moment_service.dart's doc comment for why this has to be a
  // stored, queryable field rather than a live lookup). Every room this app
  // creates is public, so this is always `['public']` — VoiceRoomService
  // .createRoom always seeds it that way. The list shape (rather than a
  // plain bool) is kept only so firestore.rules and any older room document
  // written before rooms were public-only keep working unchanged; there's
  // no UI left to create anything else. firestore.rules gates both the room
  // doc and its participants/comments/whiteboard subcollections on
  // `audience.hasAny(['public', uid])`.
  final List<String> audience;
  final DateTime? createdAt;

  const VoiceRoom({
    this.id = '',
    this.hostId = '',
    required this.title,
    required this.hostName,
    required this.hostAvatar,
    required this.hostFlag,
    required this.category,
    required this.tag,
    this.coverGradientSeed = 'a',
    this.participantAvatars = const [],
    this.participantCount = 1,
    this.isTop = false,
    this.isCreator = false,
    this.isActive = true,
    this.audience = const ['public'],
    this.createdAt,
  });

  factory VoiceRoom.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return VoiceRoom(
      id: doc.id,
      hostId: data['hostId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      hostName: data['hostName']?.toString() ?? 'Host',
      hostAvatar: data['hostAvatar']?.toString() ?? '',
      hostFlag: data['hostFlag']?.toString() ?? '🇺🇸',
      category: data['category']?.toString() ?? 'EN',
      tag: data['tag']?.toString() ?? 'General',
      coverGradientSeed: data['coverGradientSeed']?.toString() ?? 'a',
      participantAvatars: (data['participantAvatars'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      participantCount: (data['participantCount'] as num?)?.toInt() ?? 1,
      isTop: data['isTop'] == true,
      isCreator: data['isCreator'] == true,
      isActive: data['isActive'] != false,
      audience: (data['audience'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['public'],
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'hostId': hostId,
      'title': title,
      'hostName': hostName,
      'hostAvatar': hostAvatar,
      'hostFlag': hostFlag,
      'category': category,
      'tag': tag,
      'coverGradientSeed': coverGradientSeed,
      'participantAvatars': participantAvatars,
      'participantCount': participantCount,
      'isTop': isTop,
      'isCreator': isCreator,
      'isActive': true,
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
