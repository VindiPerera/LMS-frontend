import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HelloTalk', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {}),
          IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () {}),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        itemCount: mockChats.length,
        separatorBuilder: (context, i) => const Divider(height: 1, indent: 84, color: AppColors.divider),
        itemBuilder: (context, i) {
          final chat = mockChats[i];
          return InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ChatDetailScreen(user: chat.user)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  AppAvatar.forUser(chat.user, size: 54, showOnlineDot: true, showFlag: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.user.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              chat.time,
                              style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: chat.isTyping
                                  ? const Text(
                                      'typing...',
                                      style: TextStyle(color: AppColors.primaryPurple, fontSize: 13.5),
                                    )
                                  : Text(
                                      chat.lastMessage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
                                    ),
                            ),
                            if (chat.isMuted)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.notifications_off_outlined,
                                    size: 15, color: AppColors.textTertiary),
                              ),
                            if (chat.unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: const BoxDecoration(
                                  color: AppColors.badgeRed,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                child: Text(
                                  '${chat.unreadCount}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
