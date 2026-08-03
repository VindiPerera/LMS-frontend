enum RoomMessageIcon { none, notice, gift, translate, star }

class RoomParticipant {
  final String name;
  final String flag;
  final bool isHost;
  final bool isSpeaking;
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
    required this.name,
    required this.flag,
    this.isHost = false,
    this.isSpeaking = false,
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
