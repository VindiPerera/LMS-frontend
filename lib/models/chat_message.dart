import 'user.dart';

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

enum MessageType { text, image, voice, correction }

class ChatMessage {
  final String text;
  final bool isMe;
  final String time;
  final MessageType type;
  final int voiceSeconds;

  const ChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
    this.type = MessageType.text,
    this.voiceSeconds = 0,
  });
}
