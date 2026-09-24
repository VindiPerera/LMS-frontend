import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/api_config.dart';

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
  // 'host' | 'moderator' | 'speaker' | 'listener'. Host/moderator/speaker
  // occupy a grid seat; only host/moderator can moderate (remove from
  // stage, end the room, edit the whiteboard).
  final String role;
  final bool isMuted;
  // Waiting to be invited onto the stage — RoomParticipantService.
  // setHandRaised/streamRaisedHands. Only ever meaningful for a
  // non-seated (audience) participant; a seat holder has nothing left to
  // ask for.
  final bool handRaised;
  // A host/moderator-initiated invite to the stage is awaiting this
  // participant's own Accept/Ignore — RoomParticipantService.
  // sendStageInvite/streamStageInvitePending. The mirror image of
  // [handRaised]: that one is the audience asking to come up, this one is
  // the host/moderator asking them to.
  final bool stageInvitePending;
  final bool isEmptySeat;
  final String gender;
  final int age;
  final String nativeLang;
  final String learningLang;
  final String location;
  final String nativeLanguageFull;
  final List<String> learningLanguagesFull;
  final List<String> hobbies;
  // Last heartbeat write (RoomParticipantService.heartbeat) — null for the
  // instant between join() and their first heartbeat, or for the
  // decorative RoomParticipant.emptySeat placeholder. Used purely to spot
  // participants who disconnected without a clean leave(); see
  // RoomParticipantService.sweepStaleParticipants.
  final DateTime? lastActiveAt;

  const RoomParticipant({
    this.uid = '',
    required this.name,
    this.avatarUrl = '',
    required this.flag,
    this.role = 'listener',
    this.isMuted = false,
    this.handRaised = false,
    this.stageInvitePending = false,
    this.isEmptySeat = false,
    this.gender = 'female',
    this.age = 0,
    this.nativeLang = 'EN',
    this.learningLang = 'EN',
    this.location = '',
    this.nativeLanguageFull = '',
    this.learningLanguagesFull = const [],
    this.hobbies = const [],
    this.lastActiveAt,
  });

  static const emptySeat = RoomParticipant(name: '', flag: '', isEmptySeat: true);

  bool get isHost => role == 'host';
  bool get isModerator => role == 'moderator';

  // Host or a live moderator — the two tiers that can remove someone from
  // stage, end the room, and edit the whiteboard. See RoomParticipantService
  // and firestore.rules for where this same host-or-moderator check is
  // enforced server-side.
  bool get canModerate => isHost || isModerator;

  // Occupies one of the grid's speaker seats.
  bool get isSeated => role == 'host' || role == 'moderator' || role == 'speaker';

  // Drives the on-air mic badge in the speaker grid — only shown for a
  // seated, currently-unmuted participant.
  bool get isSpeaking => isSeated && !isMuted;

  factory RoomParticipant.fromFirestore(String uid, Map<String, dynamic> data) {
    return RoomParticipant(
      uid: uid,
      name: data['name']?.toString() ?? 'User',
      avatarUrl: ApiConfig.resolveUrl(data['avatarUrl']?.toString() ?? ''),
      flag: data['countryFlag']?.toString() ?? '',
      role: data['role']?.toString() ?? 'listener',
      isMuted: data['isMuted'] != false,
      handRaised: data['handRaised'] == true,
      stageInvitePending: data['stageInvitePending'] == true,
      gender: data['gender']?.toString() ?? 'other',
      age: (data['age'] as num?)?.toInt() ?? 0,
      nativeLang: data['nativeLang']?.toString() ?? '',
      learningLang: data['learningLang']?.toString() ?? '',
      hobbies: (data['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      lastActiveAt: data['lastActiveAt'] is Timestamp ? (data['lastActiveAt'] as Timestamp).toDate() : null,
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
  /// Firestore uid of the sender — used as the avatar seed so two users with
  /// the same display name never share a generated avatar.
  final String senderId;
  final String sender;
  final String text;

  const BoardComment({
    required this.senderId,
    required this.sender,
    required this.text,
  });
}

/// One live caption line — backed by `voiceRooms/{roomId}/subtitles`
/// (RoomParticipantService.addSubtitleLine/streamSubtitles). [text] is
/// already the English translation of what [speakerName] said; no actual
/// speech-to-text/translation pipeline writes these yet, but the model and
/// its Firestore-backed read/write path exist so one can be plugged in later
/// without any UI changes — mirrors [BoardComment]/the `comments`
/// subcollection exactly.
class SubtitleLine {
  final String speakerId;
  final String speakerName;
  final String text;

  const SubtitleLine({
    required this.speakerId,
    required this.speakerName,
    required this.text,
  });
}
