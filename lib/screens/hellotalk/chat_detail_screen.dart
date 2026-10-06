import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/chat_service.dart';
import '../../services/partner_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/room_participant_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/chat_time.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/voice_room_invite_card.dart';
import '../voiceroom/open_voice_room.dart';

class ChatDetailScreen extends StatefulWidget {
  final AppUser user;
  const ChatDetailScreen({super.key, required this.user});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final String _chatId = ChatService.chatIdFor(widget.user.id);
  late final Stream<List<ChatMessage>> _messagesStream =
      ChatService.streamMessages(_chatId);
  // Live online/offline for the header — widget.user.isOnline alone would
  // just be whatever was true the moment this screen opened, never
  // updating while the chat stays open. Skipped for the FaceTalk system
  // account: it isn't a real user doc, so there's nothing to listen to.
  late final Stream<bool> _theirOnlineStream = _isSystemChat
      ? const Stream.empty()
      : PartnerService.streamIsOnline(widget.user.id);
  // widget.user.avatarUrl is a denormalized participantInfo snapshot —
  // only refreshed when either side next sends a message in this thread
  // (see ChatService's class doc) — so a newly-uploaded avatar needs its
  // own live listener to show up here right away instead of waiting for
  // that next message.
  late final Stream<String?> _theirAvatarStream = _isSystemChat
      ? const Stream.empty()
      : PartnerService.streamAvatarUrl(widget.user.id);
  // The voice room they're actually, currently present in — NOT
  // PartnerService.streamActiveRoomId's raw users/{uid}.activeRoomId, which
  // only self-clears via RoomParticipantService.leave and so can stay
  // stuck pointing at a room long after they've actually left it (crash,
  // force-kill, lost connection — see that method's own doc comment on the
  // stale-participant sweep deliberately not touching this field). This
  // cross-checks their actual non-stale participant doc instead, the same
  // source of truth partner_profile_screen.dart's "Go Look" card uses.
  late final Stream<VoiceRoom?> _theirActiveRoomStream = _isSystemChat
      ? const Stream.empty()
      : RoomParticipantService.streamRoomUserIsIn(widget.user.id);

  bool get _isSystemChat => ChatService.isSystemChat(widget.user.id);

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: clears my unread count for this thread now that
    // it's open. Silently no-ops if the thread doesn't exist yet.
    ChatService.markRead(_chatId);
    // While this thread is open, a "new message" push for it would just be
    // a redundant banner on top of the message already appearing live in
    // the list below — see push_notification_service.dart.
    PushNotificationService.instance.setActiveChat(_chatId);
  }

  @override
  void dispose() {
    if (PushNotificationService.instance.activeChatId == _chatId) {
      PushNotificationService.instance.setActiveChat(null);
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await ChatService.sendMessage(other: widget.user, text: text);
      _scrollToBottom();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message ?? "Message didn't send."),
            backgroundColor: AppColors.badgeRed,
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text("Message didn't send: ${e.toString()}"),
            backgroundColor: AppColors.badgeRed,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: StreamBuilder<bool>(
          stream: _theirOnlineStream,
          initialData: widget.user.isOnline,
          builder: (context, snapshot) {
            final isOnline = snapshot.data ?? false;
            return Row(
              children: [
                // Built directly (not via AppAvatar.forUser) so the dot
                // uses the live `isOnline` above instead of the static
                // widget.user.isOnline snapshot forUser would read.
                StreamBuilder<String?>(
                  stream: _theirAvatarStream,
                  initialData: widget.user.avatarUrl.isEmpty ? null : widget.user.avatarUrl,
                  builder: (context, avatarSnapshot) {
                    return AppAvatar(
                      seed: widget.user.name,
                      imageUrl: avatarSnapshot.data,
                      size: 36,
                      showFlag: false,
                      showOnlineDot: !_isSystemChat,
                      isOnline: isOnline,
                    );
                  },
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.user.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_isSystemChat) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 15,
                            color: AppColors.primaryPurple,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _isSystemChat
                          ? 'Official account'
                          : (isOnline ? 'Active now' : 'Offline'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _isSystemChat
                            ? AppColors.textTertiary
                            : (isOnline ? AppColors.online : AppColors.textTertiary),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: _isSystemChat
            ? const []
            : [
                IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () {},
                ),
              ],
      ),
      body: Column(
        children: [
          StreamBuilder<VoiceRoom?>(
            stream: _theirActiveRoomStream,
            builder: (context, roomSnapshot) {
              final room = roomSnapshot.data;
              // streamRoomUserIsIn already only considers active, visible
              // rooms where their participant doc is actually present and
              // non-stale, so a null here covers "not in a room", "room
              // ended", and "their session went stale" all at once.
              if (room == null) return const SizedBox.shrink();
              return _PartnerVoiceRoomBanner(room: room);
            },
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.primaryPurple,
                    ),
                  );
                }

                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3EFFF),
                              shape: BoxShape.circle,
                            ),
                            child: Image.asset(
                              'assets/images/say_hi_hand.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Say hi to ${widget.user.name} 👋',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Start practicing languages and chat together!',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }


                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _MessageBubble(
                    message: messages[i],
                    user: widget.user,
                    myUid: myUid,
                  ),
                );
              },
            ),
          ),
          _isSystemChat
              ? const _ReadOnlyNotice()
              : _Composer(controller: _controller, onSend: _send),
        ],
      ),
    );
  }
}

/// Banner shown atop a chat thread while the OTHER person is currently in a
/// live Voice Room — any role (host/moderator/speaker/listener), not just
/// hosting (see _theirActiveRoomStream). Tapping it (or "Go Look") opens
/// that room via the normal openVoiceRoom entry point, ban check included.
class _PartnerVoiceRoomBanner extends StatelessWidget {
  final VoiceRoom room;
  const _PartnerVoiceRoomBanner({required this.room});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openVoiceRoom(context, room),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: AppColors.primaryPurple, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'In the Voiceroom',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      room.title,
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => openVoiceRoom(context, room),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Go Look', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final AppUser user;
  final String myUid;
  const _MessageBubble({
    required this.message,
    required this.user,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMine(myUid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            AppAvatar.forUser(user, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(child: _bubbleContent(context, isMe)),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _bubbleContent(BuildContext context, bool isMe) {
    final bg = isMe ? AppColors.primaryPurple : AppColors.surfaceLight;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );
    final timeLabel = message.createdAt != null
        ? formatChatTime(message.createdAt!)
        : '';

    if (message.type == MessageType.voiceRoomInvite) {
      // No bubble chrome around this one — VoiceRoomInviteCard already has
      // its own gradient "card" look (matching the in-room share banner),
      // so wrapping it in the usual purple/gray bubble would just double up
      // the background. Capped to a comfortable card width rather than
      // stretching edge-to-edge like a text bubble would.
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: VoiceRoomInviteCard(
          roomId: message.roomId,
          title: message.roomTitle,
          hostName: message.roomHostName,
          hostAvatar: message.roomHostAvatar,
        ),
      );
    }

    if (message.type == MessageType.voice) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            const SizedBox(width: 60, child: _VoiceWave()),
            const SizedBox(width: 6),
            Text(
              '0:${message.voiceSeconds.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          child: Text(
            message.text,
            style: TextStyle(
              color: isMe ? Colors.white : AppColors.textPrimary,
              fontSize: 14.5,
            ),
          ),
        ),
        if (message.type == MessageType.correction)
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: AppColors.perfectGreen,
                ),
                SizedBox(width: 4),
                Text(
                  'Perfect!',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.perfectGreen,
                  ),
                ),
              ],
            ),
          ),
        if (timeLabel.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            timeLabel,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary,
            ),
          ),
        ],
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
          .map(
            (h) => Container(
              width: 2.5,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white70,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Shown instead of [_Composer] for the FaceTalk system/broadcast thread —
/// replies aren't offered at all, rather than a text field that would just
/// fail (see firestore.rules' `isReadOnly` guard on chats/{chatId}/messages).
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              'Official announcements — you can\'t reply here',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _Composer({required this.controller, required this.onSend});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

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
            IconButton(
              icon: const Icon(Icons.mic_none_rounded),
              onPressed: () {},
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: widget.controller,
                  style: const TextStyle(fontSize: 14.5),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: AppColors.textTertiary),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            if (_hasText)
              IconButton(
                icon: const Icon(
                  Icons.send_rounded,
                  color: AppColors.primaryPurple,
                ),
                onPressed: widget.onSend,
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.translate_rounded),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded),
                onPressed: () {},
              ),
            ],
          ],
        ),
      ),
    );
  }
}
