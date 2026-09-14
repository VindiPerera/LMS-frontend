import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/room_participant.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/friend_service.dart';
import '../../services/notification_service.dart';
import '../../services/partner_service.dart';
import '../../services/room_participant_service.dart';
import '../../services/voice_room_service.dart';
import '../../widgets/app_avatar.dart';
import 'room_profile_sheet.dart';

class VoiceRoomDetailScreen extends StatefulWidget {
  final VoiceRoom room;
  // True only for the one navigation that immediately follows
  // VoiceRoomService.createRoom — see voiceroom_screen.dart's
  // _openCreateRoomSheet. Never set when opening an already-live room
  // (browsing the feed, a profile's room card, the "you're hosting"
  // banner), so the mic reminder below only ever appears once, right as
  // the host's own room comes up.
  final bool justCreated;
  const VoiceRoomDetailScreen({super.key, required this.room, this.justCreated = false});

  @override
  State<VoiceRoomDetailScreen> createState() => _VoiceRoomDetailScreenState();
}

class _VoiceRoomDetailScreenState extends State<VoiceRoomDetailScreen> {
  final _controller = TextEditingController();
  bool _subtitlesOn = false;
  bool _ending = false;

  static const bg = Color(0xFF1B1B3A);
  static const bubble = Color(0xFF272753);

  // Only a room with a real Firestore id/hostId (i.e. not one of the
  // decorative mock_data.dart entries) can actually be ended or invited to.
  bool get _isHost =>
      widget.room.id.isNotEmpty &&
      widget.room.hostId.isNotEmpty &&
      widget.room.hostId == FirebaseAuth.instance.currentUser?.uid;

  // The real roster (voiceRooms/{roomId}/participants) this screen renders
  // — replaces the old boardSpeakers/boardComments mock data, which looked
  // identical on every room regardless of who actually joined.
  late final Stream<List<RoomParticipant>> _participantsStream =
      RoomParticipantService.streamParticipants(widget.room.id);
  late final Stream<List<BoardComment>> _commentsStream =
      RoomParticipantService.streamRecentComments(widget.room.id);

  @override
  void initState() {
    super.initState();
    if (widget.room.id.isNotEmpty) {
      RoomParticipantService.join(roomId: widget.room.id, isHost: _isHost).catchError((e) {
        debugPrint('Failed to join room ${widget.room.id}: $e');
      });
    }
    if (widget.justCreated) {
      // Wait for the first frame — this Scaffold (and the ScaffoldMessenger
      // above it) isn't reliably attached yet during initState itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: bubble,
            duration: const Duration(seconds: 4),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            content: const Row(
              children: [
                Icon(Icons.mic_off_rounded, color: Colors.white70, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Please mute your microphone when you are not speaking.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.room.id.isNotEmpty) {
      // Fire-and-forget: the screen is already closing, nothing left to
      // await into. RoomParticipantService.leave swallows its own errors.
      RoomParticipantService.leave(widget.room.id);
    }
    super.dispose();
  }

  RoomParticipant? _findMe(List<RoomParticipant> participants) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    for (final p in participants) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  // Host first (regardless of join order — reopening your own room
  // shouldn't bump you out of seat 0), then other speakers by join order,
  // padded with empty seats out to the grid's usual size. Never truncated,
  // so a rare race in requestToSpeak can add an extra row rather than ever
  // silently dropping someone who's actually on stage.
  List<RoomParticipant> _buildSeats(List<RoomParticipant> participants) {
    final host = participants.where((p) => p.isHost);
    final otherSpeakers = participants.where((p) => p.role == 'speaker');
    final seats = [...host, ...otherSpeakers];
    final seatCount = seats.length > RoomParticipantService.speakerSeats
        ? seats.length
        : RoomParticipantService.speakerSeats;
    while (seats.length < seatCount) {
      seats.add(RoomParticipant.emptySeat);
    }
    return seats;
  }

  Future<void> _confirmEndRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this room?'),
        content: const Text('Everyone listening will be disconnected. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End Room', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _ending = true);
    try {
      await VoiceRoomService.endRoom(widget.room.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _ending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to end room: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _openInviteSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: bubble,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InviteFriendsSheet(roomId: widget.room.id),
    );
  }

  Future<void> _sendComment() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    try {
      await RoomParticipantService.sendComment(roomId: widget.room.id, text: text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _toggleMic(RoomParticipant? me) async {
    if (me == null || !me.isSeated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raise your hand to get a speaker seat first.')),
      );
      return;
    }
    try {
      await RoomParticipantService.setMuted(widget.room.id, !me.isMuted);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update mic: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _requestToSpeak(RoomParticipant? me) async {
    if (me != null && me.isSeated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're already on stage.")),
      );
      return;
    }
    try {
      await RoomParticipantService.requestToSpeak(widget.room.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: StreamBuilder<List<RoomParticipant>>(
          stream: _participantsStream,
          builder: (context, snapshot) {
            final participants = snapshot.data ?? const <RoomParticipant>[];
            final me = _findMe(participants);
            final seats = _buildSeats(participants);
            final listeners = participants.where((p) => !p.isSeated).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      _actionChip('Add images', Icons.add_photo_alternate_outlined),
                      const SizedBox(width: 8),
                      _actionChip('Type text', Icons.text_fields_rounded),
                      const Spacer(),
                      if (_isHost) ...[
                        _actionChip('Invite', Icons.person_add_alt_1_rounded, onTap: _openInviteSheet),
                        const SizedBox(width: 8),
                        _ending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                              )
                            : _actionChip('End Room', Icons.call_end_rounded, onTap: _confirmEndRoom),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2ECC71),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: AspectRatio(
                          aspectRatio: 1.8,
                          child: Stack(
                            children: [
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              const Positioned(
                                right: 10,
                                bottom: 10,
                                child: Icon(
                                  Icons.open_in_full_rounded,
                                  color: Colors.white38,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 4,
                                childAspectRatio: 1.05,
                              ),
                          itemCount: seats.length,
                          itemBuilder: (context, i) {
                            final speaker = seats[i];
                            return GestureDetector(
                              onTap: speaker.isEmptySeat
                                  ? () => _requestToSpeak(me)
                                  : () => showRoomProfileSheet(
                                        context,
                                        speaker,
                                        roomId: widget.room.id,
                                        isViewerHost: _isHost,
                                      ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  speaker.isEmptySeat
                                      ? Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: Colors.white12,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white38,
                                              width: 1,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.front_hand_rounded,
                                            color: Colors.white38,
                                            size: 22,
                                          ),
                                        )
                                      : Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            AppAvatar(
                                              seed: speaker.uid.isNotEmpty ? speaker.uid : '${speaker.name}$i',
                                              size: 56,
                                              showFlag: true,
                                              flag: speaker.flag,
                                              imageUrl: speaker.avatarUrl,
                                              borderWidth: speaker.isSpeaking
                                                  ? 2.5
                                                  : 0,
                                              borderColor: const Color(0xFF3DDC97),
                                            ),
                                            if (speaker.isSpeaking)
                                              Positioned(
                                                right: -2,
                                                top: -2,
                                                child: Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFF3DDC97),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.mic_rounded,
                                                    color: Colors.white,
                                                    size: 11,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                  const SizedBox(height: 4),
                                  Text(
                                    speaker.isEmptySeat ? '${i + 1}' : speaker.name,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 44,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white24, width: 1.4),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Builder(
                              builder: (context) {
                                const previewCount = 7;
                                final preview = listeners.take(previewCount).toList();
                                final remaining = listeners.length - preview.length;
                                if (preview.isEmpty) {
                                  return const Row(
                                    children: [
                                      Text(
                                        'No one in the audience yet',
                                        style: TextStyle(fontSize: 12, color: Colors.white38),
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    for (final listener in preview)
                                      AppAvatar(
                                        seed: listener.uid.isNotEmpty ? listener.uid : listener.name,
                                        size: 32,
                                        imageUrl: listener.avatarUrl,
                                      ),
                                    if (remaining > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 8,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: Colors.white12,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '+$remaining',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: StreamBuilder<List<BoardComment>>(
                                stream: _commentsStream,
                                builder: (context, commentsSnap) {
                                  final comments = commentsSnap.data ?? const <BoardComment>[];
                                  if (comments.isEmpty) return const SizedBox.shrink();
                                  return Column(
                                    children: comments.map((c) => _CommentLine(comment: c)).toList(),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SubtitlesButton(
                              enabled: _subtitlesOn,
                              onTap: () =>
                                  setState(() => _subtitlesOn = !_subtitlesOn),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _Composer(
                  controller: _controller,
                  me: me,
                  onSend: _sendComment,
                  onToggleMic: () => _toggleMic(me),
                  onRaiseHand: () => _requestToSpeak(me),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, {VoidCallback? onTap}) {
    final isDanger = onTap != null && icon == Icons.call_end_rounded;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDanger ? Colors.red.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDanger ? Colors.redAccent : Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: isDanger ? Colors.redAccent : Colors.white54),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// Bottom sheet listing the host's friends, each with an "Invite" button
/// that writes a `voiceRoomInvites` doc — functions/index.js's
/// onVoiceRoomInviteCreate turns that into a real push + in-app
/// notification for the invited friend. See NotificationService.inviteToVoiceRoom.
class _InviteFriendsSheet extends StatefulWidget {
  final String roomId;
  const _InviteFriendsSheet({required this.roomId});

  @override
  State<_InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends State<_InviteFriendsSheet> {
  late final Future<List<AppUser>> _friendsFuture = _loadFriends();
  final Set<String> _invited = {};

  Future<List<AppUser>> _loadFriends() async {
    final friendIds = await FriendService.instance.getFriendIds();
    final users = await Future.wait(
      friendIds.map((id) async {
        try {
          return await PartnerService.fetchPartner(id);
        } catch (_) {
          return null;
        }
      }),
    );
    return users.whereType<AppUser>().toList();
  }

  Future<void> _invite(AppUser friend) async {
    setState(() => _invited.add(friend.id));
    try {
      await NotificationService.inviteToVoiceRoom(recipientId: friend.id, roomId: widget.roomId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _invited.remove(friend.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not invite ${friend.name}: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Invite friends',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 320,
              child: FutureBuilder<List<AppUser>>(
                future: _friendsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    );
                  }
                  final friends = snapshot.data ?? const [];
                  if (friends.isEmpty) {
                    return const Center(
                      child: Text(
                        'Add some friends first to invite them here.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: friends.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final friend = friends[i];
                      final invited = _invited.contains(friend.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AppAvatar(seed: friend.name, size: 40, imageUrl: friend.avatarUrl),
                        title: Text(friend.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        trailing: TextButton(
                          onPressed: invited ? null : () => _invite(friend),
                          child: Text(
                            invited ? 'Invited' : 'Invite',
                            style: TextStyle(color: invited ? Colors.white38 : const Color(0xFF7B68F4)),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtitlesButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SubtitlesButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Subtitles',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: enabled ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CommentLine extends StatelessWidget {
  final BoardComment comment;
  const _CommentLine({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppAvatar(seed: comment.sender, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${comment.sender}  ·  ',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: comment.text,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final RoomParticipant? me;
  final VoidCallback onSend;
  final VoidCallback onToggleMic;
  final VoidCallback onRaiseHand;
  const _Composer({
    required this.controller,
    required this.me,
    required this.onSend,
    required this.onToggleMic,
    required this.onRaiseHand,
  });

  @override
  Widget build(BuildContext context) {
    final isSeated = me?.isSeated ?? false;
    final isUnmuted = isSeated && !(me?.isMuted ?? true);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _VoiceRoomDetailScreenState.bubble,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Comments...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12.5),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onToggleMic,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isUnmuted ? const Color(0xFF3DDC97) : const Color(0xFF4FA8FF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUnmuted ? Icons.mic_rounded : Icons.mic_off_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRaiseHand,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSeated ? Colors.white24 : const Color(0xFF7B68F4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.front_hand_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
