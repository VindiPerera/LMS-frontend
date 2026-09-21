import 'package:cloud_firestore/cloud_firestore.dart';
import 'user.dart';

/// One row in the chat list (hellotalk/chat_list_screen.dart): the other
/// participant's profile (denormalized onto the chat document — see
/// ChatService — so the list can render without an extra Firestore read per
/// row) plus a preview of the thread's last message.
class ChatPreview {
  final AppUser user;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isTyping;
  final bool isMuted;

  const ChatPreview({
    required this.user,
    required this.lastMessage,
    required this.time,
    this.unreadCount = 0,
    this.isTyping = false,
    this.isMuted = false,
  });
}

enum MessageType { text, image, voice, correction, voiceRoomInvite }

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
      roomId: data['roomId']?.toString() ?? '',
      roomTitle: data['roomTitle']?.toString() ?? '',
      roomHostName: data['roomHostName']?.toString() ?? '',
      roomHostAvatar: data['roomHostAvatar']?.toString() ?? '',
      roomCategory: data['roomCategory']?.toString() ?? '',
      roomTag: data['roomTag']?.toString() ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
