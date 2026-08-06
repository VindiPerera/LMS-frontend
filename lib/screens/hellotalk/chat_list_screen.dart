import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../services/chat_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'add_contact_screen.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // Cached once so a widget rebuild doesn't attach a second Firestore
  // listener on top of the first.
  late final Stream<List<ChatPreview>> _chatsStream =
      ChatService.streamChatPreviews();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FaceTalk',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => AddContactScreen.show(context),
          ),
        ],
      ),
      body: StreamBuilder<List<ChatPreview>>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Could not load your chats.',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primaryPurple,
              ),
            );
          }

          final chats = snapshot.data!;
          if (chats.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 44,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No conversations yet',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Say hi to someone from Connect to start chatting.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            itemCount: chats.length,
            separatorBuilder: (context, i) =>
                const Divider(height: 1, indent: 84, color: AppColors.divider),
            itemBuilder: (context, i) => _ChatListTile(chat: chats[i]),
          );
        },
      ),
    );
  }
}

class _ChatListTile extends StatelessWidget {
  final ChatPreview chat;
  const _ChatListTile({required this.chat});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatDetailScreen(user: chat.user)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AppAvatar.forUser(
              chat.user,
              size: 54,
              showOnlineDot: true,
              showFlag: true,
            ),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        chat.time,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
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
                                style: TextStyle(
                                  color: AppColors.primaryPurple,
                                  fontSize: 13.5,
                                ),
                              )
                            : Text(
                                chat.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13.5,
                                ),
                              ),
                      ),
                      if (chat.isMuted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.notifications_off_outlined,
                            size: 15,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      if (chat.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.badgeRed,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Text(
                            '${chat.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
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
  }
}
