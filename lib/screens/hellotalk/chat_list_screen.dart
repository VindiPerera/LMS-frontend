import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../models/voiceroom.dart';
import '../../services/chat_service.dart';
import '../../services/partner_service.dart';
import '../../services/room_participant_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'add_contact_screen.dart';
import '../connect/partner_profile_screen.dart';
import 'chat_detail_screen.dart';
import '../voiceroom/open_voice_room.dart';

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

  // Live online status per chat partner, keyed by uid — used only to sort
  // the list (online first). chat.user.isOnline itself is a stale,
  // always-false denormalized snapshot (see _ChatListTile's own doc
  // comment on its avatar's identical live-vs-snapshot distinction), so
  // sorting needs its own up-to-date source, same as each row's indicator
  // already has independently for display.
  final Map<String, bool> _onlineByUid = {};
  final Map<String, StreamSubscription<bool>> _onlineSubs = {};
  StreamSubscription<List<ChatPreview>>? _chatsSub;

  @override
  void initState() {
    super.initState();
    _chatsSub = _chatsStream.listen(_syncOnlineSubscriptions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatsSub?.cancel();
    for (final sub in _onlineSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Keeps exactly one live online-status listener per uid currently in the
  /// chat list — added the first time a partner's chat appears, removed
  /// once it no longer does — so sorting always reflects current status
  /// without polling or re-subscribing on every rebuild.
  void _syncOnlineSubscriptions(List<ChatPreview> chats) {
    final ids = chats.map((c) => c.user.id).where((id) => id.isNotEmpty).toSet();
    for (final gone in _onlineSubs.keys.where((id) => !ids.contains(id)).toList()) {
      _onlineSubs.remove(gone)?.cancel();
      _onlineByUid.remove(gone);
    }
    for (final id in ids) {
      if (_onlineSubs.containsKey(id)) continue;
      _onlineSubs[id] = PartnerService.streamIsOnline(id).listen((isOnline) {
        if (!mounted) return;
        if (_onlineByUid[id] == isOnline) return;
        setState(() => _onlineByUid[id] = isOnline);
      });
    }
  }

  /// Online partners first, offline last. A plain partition (not
  /// List.sort, which Dart doesn't guarantee is stable) — each group is
  /// built by walking [chats] once in its existing order and appending, so
  /// within each group chats keep whatever order they already had (newest
  /// message first, per ChatService.streamChatPreviews), matching "offline
  /// users appear... in the existing order" exactly.
  List<ChatPreview> _sortedChats(List<ChatPreview> chats) {
    final online = <ChatPreview>[];
    final offline = <ChatPreview>[];
    for (final chat in chats) {
      final isOnline = _onlineByUid[chat.user.id] ?? false;
      (isOnline ? online : offline).add(chat);
    }
    return [...online, ...offline];
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
          final filteredChats = _sortedChats(chats.where((chat) {
            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            return chat.user.name.toLowerCase().contains(q) ||
                chat.user.handle.toLowerCase().contains(q) ||
                chat.lastMessage.toLowerCase().contains(q);
          }).toList());

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
                      // While searching, a tapped result opens that user's profile
                      // (with its live "Go Look" voice-room card); the normal,
                      // un-searched list still opens the chat as before.
                      return _ChatListTile(chat: chat, openProfile: _searchQuery.isNotEmpty);
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
  final bool openProfile;
  const _ChatListTile({required this.chat, this.openProfile = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => openProfile
              ? PartnerProfileScreen(initial: chat.user)
              : ChatDetailScreen(user: chat.user),
        ),
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
            // User Avatar with online/voice-room indicator and country flag.
            // The isOnline on chat.user itself is a denormalized snapshot
            // from whenever a message was last sent (see ChatService
            // ._infoFor, which doesn't even carry isOnline — it's always
            // the AppUser default of false) — genuinely live status needs
            // its own listener, same as chat_detail_screen.dart's header.
            StreamBuilder<bool>(
              stream: PartnerService.streamIsOnline(chat.user.id),
              initialData: chat.user.isOnline,
              builder: (context, onlineSnapshot) {
                return StreamBuilder<VoiceRoom?>(
                  // RoomParticipantService.streamRoomUserIsIn, not the raw
                  // users/{uid}.activeRoomId field — that field only ever
                  // self-clears via RoomParticipantService.leave, so a
                  // client that died without calling it (crash, force-kill,
                  // lost connection) would otherwise leave this badge stuck
                  // on even after the room's own stale-participant sweep
                  // has already removed them from the room. This stream
                  // cross-checks their actual (non-stale) participant doc
                  // instead, same source of truth partner_profile_screen
                  // .dart's "Go Look" card already relies on.
                  stream: RoomParticipantService.streamRoomUserIsIn(chat.user.id),
                  builder: (context, roomSnapshot) {
                    return StreamBuilder<String?>(
                      // chat.user.avatarUrl is that same denormalized
                      // participantInfo snapshot — only refreshed when
                      // either side next sends a message (see ChatService's
                      // class doc) — so a newly-uploaded avatar needs its
                      // own live listener too, same reasoning as isOnline
                      // above, to show up here right away.
                      stream: PartnerService.streamAvatarUrl(chat.user.id),
                      initialData: chat.user.avatarUrl.isEmpty ? null : chat.user.avatarUrl,
                      builder: (context, avatarSnapshot) {
                        return AppAvatar(
                          seed: chat.user.name,
                          size: 54,
                          showOnlineDot: true,
                          isOnline: onlineSnapshot.data ?? false,
                          inVoiceRoom: roomSnapshot.data != null,
                          showFlag: true,
                          flag: chat.user.countryFlag,
                          imageUrl: avatarSnapshot.data,
                        );
                      },
                    );
                  },
                );
              },
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
          onTap: () => openVoiceRoom(context, room),
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

