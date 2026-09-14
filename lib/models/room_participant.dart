enum RoomMessageIcon { none, notice, gift, translate, star }

/// One person present in a voice room — backed by
/// `voiceRooms/{roomId}/participants/{uid}` (see RoomParticipantService).
/// [isEmptySeat] instances are never real Firestore data; they're the
/// grid-padding placeholders VoiceRoomDetailScreen inserts to fill out
/// unclaimed speaker seats.
class RoomParticipant {
  final String uid;
  final String name;
  final String avatarUrl;
  final String flag;
  // 'host' | 'speaker' | 'listener'. Only host/speaker occupy a grid seat.
  final String role;
  final bool isMuted;
  final bool isEmptySeat;
  final String gender;
  final int age;
  final String nativeLang;
  final String learningLang;
  final String location;
  final String nativeLanguageFull;
  final List<String> learningLanguagesFull;
  final List<String> hobbies;

  const RoomParticipant({
    this.uid = '',
    required this.name,
    this.avatarUrl = '',
    required this.flag,
    this.role = 'listener',
    this.isMuted = false,
    this.isEmptySeat = false,
    this.gender = 'female',
    this.age = 0,
    this.nativeLang = 'EN',
    this.learningLang = 'EN',
    this.location = '',
    this.nativeLanguageFull = '',
    this.learningLanguagesFull = const [],
    this.hobbies = const [],
  });

  static const emptySeat = RoomParticipant(name: '', flag: '', isEmptySeat: true);

  bool get isHost => role == 'host';

  // Occupies one of the grid's speaker seats (host or promoted speaker).
  bool get isSeated => role == 'host' || role == 'speaker';

  // Drives the on-air mic badge in the speaker grid — only shown for a
  // seated, currently-unmuted participant.
  bool get isSpeaking => isSeated && !isMuted;

  factory RoomParticipant.fromFirestore(String uid, Map<String, dynamic> data) {
    return RoomParticipant(
      uid: uid,
      name: data['name']?.toString() ?? 'User',
      avatarUrl: data['avatarUrl']?.toString() ?? '',
      flag: data['countryFlag']?.toString() ?? '',
      role: data['role']?.toString() ?? 'listener',
      isMuted: data['isMuted'] != false,
      gender: data['gender']?.toString() ?? 'other',
      age: (data['age'] as num?)?.toInt() ?? 0,
      nativeLang: data['nativeLang']?.toString() ?? '',
      learningLang: data['learningLang']?.toString() ?? '',
      hobbies: (data['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

class RoomChatMessage {
  final String sender;
  final String senderBadge;
  final String text;
  final bool isSystem;
  final bool isTranslated;
  final RoomMessageIcon icon;

  const RoomChatMessage({
    required this.sender,
    this.senderBadge = '',
    required this.text,
    this.isSystem = false,
    this.isTranslated = false,
    this.icon = RoomMessageIcon.none,
  });
}

class BoardComment {
  final String sender;
  final String text;

  const BoardComment({required this.sender, required this.text});
}
