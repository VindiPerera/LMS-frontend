import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

class ChatDetailScreen extends StatefulWidget {
  final AppUser user;
  const ChatDetailScreen({super.key, required this.user});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AppAvatar.forUser(widget.user, size: 36, showOnlineDot: true),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.user.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                  widget.user.isOnline ? 'Active now' : 'Offline',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: widget.user.isOnline ? AppColors.online : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              itemCount: mockConversation.length,
              itemBuilder: (context, i) {
                final msg = mockConversation[i];
                return _MessageBubble(message: msg, user: widget.user);
              },
            ),
          ),
          _Composer(controller: _controller),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final AppUser user;
  const _MessageBubble({required this.message, required this.user});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            AppAvatar.forUser(user, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(child: _bubbleContent(context)),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _bubbleContent(BuildContext context) {
    final isMe = message.isMe;
    final bg = isMe ? AppColors.primaryPurple : AppColors.surfaceLight;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    if (message.type == MessageType.voice) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            const SizedBox(
              width: 60,
              child: _VoiceWave(),
            ),
            const SizedBox(width: 6),
            Text('0:${message.voiceSeconds.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Text(
            message.text,
            style: TextStyle(color: isMe ? Colors.white : AppColors.textPrimary, fontSize: 14.5),
          ),
        ),
        if (message.type == MessageType.correction)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle_rounded, size: 13, color: AppColors.perfectGreen),
                SizedBox(width: 4),
                Text('Perfect!', style: TextStyle(fontSize: 11.5, color: AppColors.perfectGreen)),
              ],
            ),
          ),
        const SizedBox(height: 3),
        Text(message.time, style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary)),
      ],
    );
  }
}

class _VoiceWave extends StatelessWidget {
  const _VoiceWave();

  @override
  Widget build(BuildContext context) {
    final heights = [4.0, 10.0, 6.0, 14.0, 8.0, 12.0, 5.0, 9.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: heights
          .map((h) => Container(
                width: 2.5,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(2),
                ),
              ))
          .toList(),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  const _Composer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
        ),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.mic_none_rounded), onPressed: () {}),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 14.5),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: AppColors.textTertiary),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.translate_rounded), onPressed: () {}),
            IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
