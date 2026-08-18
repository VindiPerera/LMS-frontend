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
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
