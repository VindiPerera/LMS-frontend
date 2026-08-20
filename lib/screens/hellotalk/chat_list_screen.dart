import 'package:flutter/material.dart';
import '../../data/mock_data.dart' as mock;
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/chat_service.dart';
import '../../services/partner_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'add_contact_screen.dart';
import 'chat_detail_screen.dart';
import '../voiceroom/voice_room_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  late final Stream<List<ChatPreview>> _chatsStream =
      ChatService.streamChatPreviews();
  late final Stream<VoiceRoom?> _myVoiceRoomStream = VoiceRoomService.streamMyActiveRoom();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<AppUser> _onlinePartners = [];

  @override
  void initState() {
    super.initState();
    _loadOnlinePartners();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// "Active Partners" is meant to show who's genuinely online right now —
  /// filtering by isOnline here is what actually makes that true, instead
  /// of just showing any 10 partners with a decorative always-green dot.
  /// fetchPartners already orders online-first, so a higher limit costs
  /// little even though most of it gets filtered back out.
  Future<void> _loadOnlinePartners() async {
    try {
      final partners = await PartnerService.fetchPartners(limit: 30);
      final online = partners.where((p) => p.isOnline).take(10).toList();
      if (!mounted) return;
      setState(() {
        _onlinePartners = online.isNotEmpty
            ? online
            : mock.mockUsers.where((u) => u.isOnline).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _onlinePartners = mock.mockUsers.where((u) => u.isOnline).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text(
          'FaceTalk',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: -0.5,
            color: AppColors.primaryPurple,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: ElevatedButton.icon(
              onPressed: () => AddContactScreen.show(context),
              icon: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
                color: Colors.white,
              ),
              label: const Text(
                'Add People',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<ChatPreview>>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          final chats = snapshot.data ?? [];
          final filteredChats = chats.where((chat) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            return chat.user.name.toLowerCase().contains(q) ||
                chat.user.handle.toLowerCase().contains(q) ||
                chat.lastMessage.toLowerCase().contains(q);
          }).toList();

          return CustomScrollView(
            slivers: [
              // Live Voice Room banner (only shown if user is hosting)
              SliverToBoxAdapter(
                child: _LiveVoiceRoomBanner(roomStream: _myVoiceRoomStream),
              ),

              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) {
                              setState(() => _searchQuery = val.trim());
                            },
                            decoration: const InputDecoration(
                              hintText: 'Search messages & friends...',
                              hintStyle: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: const Icon(
                              Icons.cancel_rounded,
                              size: 18,
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Active Online Partners Header Bar
              if (_searchQuery.isEmpty && _onlinePartners.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(
                          'Active Partners',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 88,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _onlinePartners.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, i) {
                            final user = _onlinePartners[i];
                            return GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChatDetailScreen(user: user),
                                  ),
                                );
                              },
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primaryPurple,
                                        width: 2,
                                      ),
                                    ),
                                    // showOnlineDot ties this to the real
                                    // users/{uid}.isOnline value (kept live
                                    // by AuthService.setOnlineStatus/
                                    // main_shell.dart's app-lifecycle
                                    // observer) instead of a hardcoded dot
                                    // that showed every row as "online"
                                    // regardless of actual status.
                                    child: AppAvatar.forUser(
                                      user,
                                      size: 46,
                                      showFlag: false,
                                      showOnlineDot: true,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 58,
                                    child: Text(
                                      user.name.split(' ')[0],
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(height: 1, color: AppColors.divider),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

              // Chat List Section
              if (snapshot.connectionState == ConnectionState.waiting &&
                  chats.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                )
              else if (filteredChats.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 34,
                              color: AppColors.primaryPurple,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No chats matching "$_searchQuery"'
                                : 'No conversations yet',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Start a conversation with language partners to improve your fluency together!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => AddContactScreen.show(context),
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Find Language Partners',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final chat = filteredChats[index];
                      return _ChatListTile(chat: chat);
                    },
                    childCount: filteredChats.length,
                  ),
                ),
            ],
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 0.6),
          ),
        ),
        child: Row(
          children: [
            // User Avatar with online indicator and country flag
            AppAvatar.forUser(
              chat.user,
              size: 54,
              showOnlineDot: true,
              showFlag: true,
            ),
            const SizedBox(width: 14),

            // Message Info & Language context
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and Time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        chat.time,
                        style: TextStyle(
                          color: chat.unreadCount > 0
                              ? AppColors.primaryPurple
                              : AppColors.textTertiary,
                          fontSize: 12,
                          fontWeight: chat.unreadCount > 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Language Pair & Last Message
                  Row(
                    children: [
                      Expanded(
                        child: chat.isTyping
                            ? const Text(
                                'typing...',
                                style: TextStyle(
                                  color: AppColors.primaryPurple,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Text(
                                chat.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: chat.unreadCount > 0
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                  fontSize: 13.5,
                                  fontWeight: chat.unreadCount > 0
                                      ? FontWeight.w700
                                      : FontWeight.w400,
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
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${chat.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
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

/// Shows a compact purple banner at the top of Chat when the signed-in user
/// is currently hosting an active Voice Room, with "Return to Room" button.
class _LiveVoiceRoomBanner extends StatelessWidget {
  final Stream<VoiceRoom?> roomStream;
  const _LiveVoiceRoomBanner({required this.roomStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VoiceRoom?>(
      stream: roomStream,
      builder: (context, snapshot) {
        final room = snapshot.data;
        if (room == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VoiceRoomDetailScreen(room: room)),
            );
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8E2DE2).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    room.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Return to Room ›',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

