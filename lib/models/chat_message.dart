import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/api_config.dart';
import 'user.dart';

/// One row in the chat list (hellotalk/chat_list_screen.dart): the other
/// participant's profile (denormalized onto the chat document — see
/// ChatService — so the list can render without an extra Firestore read per
/// row) plus a preview of the thread's last message.
class ChatPreview {
  // The Firestore chats/{id} doc id — needed directly (rather than
  // re-derived via ChatService.chatIdFor) for a group thread, whose id is a
  // plain Firestore auto-id, not a deterministic function of its members.
  final String id;
  // Null for a group thread (see [isGroup]) — there's no single "other
  // participant" to represent as one AppUser. 1:1 call sites that pre-date
  // groups can keep assuming this is set by checking !isGroup first.
  final AppUser? user;
  final bool isGroup;
  final String groupName;
  final String groupAvatar;
  final int memberCount;
  // Up to a handful of (uid, name) pairs (see ChatService._previewFromDoc)
  // — GroupAvatar's default photo-collage: each bubble looks that member's
  // CURRENT photo up live from the uid, falling back to their name's
  // initial (same as AppAvatar's own no-photo fallback) rather than a bare
  // color swatch when they don't have one. Empty for a 1:1 thread.
  final List<({String uid, String name})> members;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isTyping;
  final bool isMuted;

  const ChatPreview({
    required this.id,
    this.user,
    this.isGroup = false,
    this.groupName = '',
    this.groupAvatar = '',
    this.memberCount = 0,
    this.members = const [],
    required this.lastMessage,
    required this.time,
    this.unreadCount = 0,
    this.isTyping = false,
    this.isMuted = false,
  });

  /// Display name for either shape — the group's name, or the other
  /// person's. Prefer this over reaching into [user]/[groupName] directly
  /// wherever a caller doesn't otherwise need to branch on [isGroup].
  String get displayName => isGroup ? groupName : (user?.name ?? '');
}

// `system` is a group-only, centered announcement line (created/added/
// removed/left — see ChatService.createGroup/addGroupMembers/
// removeGroupMember/leaveGroup) rather than a bubble from either side.
enum MessageType { text, image, voice, file, correction, voiceRoomInvite, system }

MessageType _typeFromString(String? value) {
  return MessageType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => MessageType.text,
  );
}

/// One message within a `chats/{chatId}/messages` document.
class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final int voiceSeconds;
  // The uploaded file's URL — set for MessageType.image/voice/file, empty
  // for a plain text message (see ChatService.sendImageMessage/
  // sendVoiceMessage/sendFileMessage, which all go through MediaService's
  // upload pipeline before writing the message doc).
  final String mediaUrl;
  // Only meaningful for MessageType.file — the original filename/size so
  // the bubble can show something more useful than a bare link (an image or
  // voice note doesn't need these: the bubble renders the photo/waveform
  // directly instead of a filename).
  final String fileName;
  final int fileSize;
  // Only set when type == voiceRoomInvite — a snapshot of the room at the
  // moment it was shared (see ChatService.sendVoiceRoomInvite), so the card
  // still shows a title/host even if the room is later renamed or has
  // ended. Live status (still active? how many people are in it now?) is
  // looked up fresh from voiceRooms/{roomId} when the card renders — see
  // VoiceRoomInviteCard.
  final String roomId;
  final String roomTitle;
  final String roomHostName;
  final String roomHostAvatar;
  final String roomCategory;
  final String roomTag;
  // Null immediately after sending, until the server timestamp round-trips
  // back down (FieldValue.serverTimestamp() reads as null on the writer's
  // own optimistic local snapshot).
  final DateTime? createdAt;

  const ChatMessage({
    this.id = '',
    required this.senderId,
    required this.text,
    this.type = MessageType.text,
    this.voiceSeconds = 0,
    this.mediaUrl = '',
    this.fileName = '',
    this.fileSize = 0,
    this.roomId = '',
    this.roomTitle = '',
    this.roomHostName = '',
    this.roomHostAvatar = '',
    this.roomCategory = '',
    this.roomTag = '',
    this.createdAt,
  });

  bool isMine(String uid) => senderId == uid;

  factory ChatMessage.fromDoc(String id, Map<String, dynamic> data) {
    final ts = data['createdAt'];
    return ChatMessage(
      id: id,
      senderId: data['senderId']?.toString() ?? '',
      text: data['text']?.toString() ?? '',
      type: _typeFromString(data['type']?.toString()),
      voiceSeconds: (data['voiceSeconds'] as num?)?.toInt() ?? 0,
      mediaUrl: ApiConfig.resolveUrl(data['mediaUrl']?.toString() ?? ''),
      fileName: data['fileName']?.toString() ?? '',
      fileSize: (data['fileSize'] as num?)?.toInt() ?? 0,
      roomId: data['roomId']?.toString() ?? '',
      roomTitle: data['roomTitle']?.toString() ?? '',
      roomHostName: data['roomHostName']?.toString() ?? '',
      roomHostAvatar: ApiConfig.resolveUrl(data['roomHostAvatar']?.toString() ?? ''),
      roomCategory: data['roomCategory']?.toString() ?? '',
      roomTag: data['roomTag']?.toString() ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// One group member's denormalized snapshot within a [ChatThread] — the
/// `participantInfo` map's per-uid shape, same fields ChatService._infoFor
/// writes (and the same shape partner_profile_screen.dart's AppUser.tags
/// doesn't need here, since this is only ever rendered as an avatar/name
/// row, never a full profile — tapping a member opens their real profile
/// via PartnerService.fetchPartner instead of trusting this snapshot for
/// anything beyond display).
class GroupMember {
  final String uid;
  final String name;
  final String avatarUrl;
  final String countryFlag;

  const GroupMember({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.countryFlag,
  });

  factory GroupMember.fromJson(String uid, Map<String, dynamic> json) {
    return GroupMember(
      uid: uid,
      name: json['name']?.toString() ?? 'User',
      avatarUrl: ApiConfig.resolveUrl(json['avatarUrl']?.toString() ?? ''),
      countryFlag: json['countryFlag']?.toString() ?? '',
    );
  }
}

/// A group chat's own live state — chat_detail_screen.dart's group header
/// and group_info_screen.dart's member list both stream this (see
/// ChatService.streamGroupThread) rather than each re-deriving it from raw
/// Firestore data, so the two screens can never drift out of sync with each
/// other on what "the current member list" even is.
class ChatThread {
  final String id;
  final String groupName;
  final String groupAvatar;
  final String adminId;
  final List<GroupMember> members;

  const ChatThread({
    required this.id,
    required this.groupName,
    required this.groupAvatar,
    required this.adminId,
    required this.members,
  });

  List<String> get memberIds => members.map((m) => m.uid).toList();

  factory ChatThread.fromDoc(String id, Map<String, dynamic> data) {
    final participants = List<String>.from(data['participants'] as List? ?? const []);
    final info = (data['participantInfo'] as Map?) ?? const {};
    return ChatThread(
      id: id,
      groupName: data['groupName']?.toString() ?? 'Group',
      groupAvatar: ApiConfig.resolveUrl(data['groupAvatar']?.toString() ?? ''),
      adminId: data['adminId']?.toString() ?? '',
      members: participants
          .map((uid) => GroupMember.fromJson(uid, (info[uid] as Map?)?.cast<String, dynamic>() ?? const {}))
          .toList(),
    );
  }
}
