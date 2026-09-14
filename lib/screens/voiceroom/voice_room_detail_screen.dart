import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/room_participant.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../models/whiteboard_item.dart';
import '../../services/friend_service.dart';
import '../../services/notification_service.dart';
import '../../services/partner_service.dart';
import '../../services/room_participant_service.dart';
import '../../services/room_share_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_room_service.dart';
import '../../services/whiteboard_service.dart';
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
  // Drives the toolbar's scrollable action-chip strip (see build()) so a
  // Scrollbar can be attached to the same controller — that's what makes
  // "there's more to scroll" visible up front instead of something the user
  // has to discover by accidentally swiping.
  final _toolbarScrollController = ScrollController();
  bool _subtitlesOn = false;
  bool _ending = false;
  bool _addingImage = false;

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
  // asBroadcastStream() is required because this stream has two listeners:
  // the StreamBuilder in build() AND the sweep subscription in initState().
  // A plain single-subscription stream would throw "Bad state: Stream has
  // already been listened to" the moment the second subscriber attaches.
  late final Stream<List<RoomParticipant>> _participantsStream =
      RoomParticipantService.streamParticipants(widget.room.id).asBroadcastStream();
  late final Stream<List<BoardComment>> _commentsStream =
      RoomParticipantService.streamRecentComments(widget.room.id);
  late final Stream<List<WhiteboardItem>> _whiteboardStream =
      WhiteboardService.streamItems(widget.room.id);

  // Watches the room doc itself (not just the participant roster) so
  // everyone still inside gets auto-popped with a notice the moment it
  // ends — otherwise only the person who tapped End Room leaves, and
  // everyone else is stranded on a now-dead room. `_ending` guards against
  // double-popping the very screen instance that triggered the end.
  StreamSubscription<VoiceRoom?>? _roomSub;

  // Presence: a periodic heartbeat while this screen is open, plus a
  // separate subscription (not the one the UI renders from) purely to
  // sweep any OTHER participant whose own heartbeat has gone stale — see
  // RoomParticipantService. Closing the tab, losing network, or crashing
  // never runs dispose(), so without this a disconnected participant would
  // occupy a seat and inflate participantCount forever.
  Timer? _heartbeatTimer;
  StreamSubscription<List<RoomParticipant>>? _sweepSub;

  // One fresh token per mount, threaded through join/heartbeat/leave — see
  // RoomParticipantService.newSessionId's doc comment for why this exists
  // (it's what stops a stale leave() from a just-closed previous mount of
  // this same screen from deleting the doc a fresh rejoin just claimed).
  final String _sessionId = RoomParticipantService.newSessionId();

  @override
  void initState() {
    super.initState();
    if (widget.room.id.isNotEmpty) {
      RoomParticipantService.join(
        roomId: widget.room.id,
        isHost: _isHost,
        sessionId: _sessionId,
      ).catchError((e) {
        debugPrint('Failed to join room ${widget.room.id}: $e');
        // Every room this app creates today is public and joinable by any
        // signed-in user, so firestore.rules should never actually reject
        // this — but it still can for a room document that predates that
        // (a restricted audience from before rooms went public-only) or one
        // whose audience was otherwise revoked. Without this, the screen
        // would otherwise just sit there looking joined while silently
        // having no seat, no roster write, nothing.
        final denied = e is FirebaseException && e.code == 'permission-denied';
        if (!denied) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _ending) return;
          _ending = true;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You don't have access to this room.")),
          );
        });
      });
      _roomSub = VoiceRoomService.streamRoom(widget.room.id).listen((room) {
        if (!mounted || _ending) return;
        if (room == null || !room.isActive) {
          // Captured before the pop — context stops being safely usable
          // for widget lookups once this screen closes, but the messenger
          // reference stays valid (same pattern as _leave/_subscribe
          // elsewhere in this app). `room == null` covers both the room
          // genuinely ending/vanishing and this device losing audience
          // access to a private room (streamRoom's handleError maps a
          // permission-denied stream error to null the same as any other).
          final message = room == null ? 'This room is no longer available.' : 'This room has ended.';
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop();
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      });
      _heartbeatTimer = Timer.periodic(RoomParticipantService.heartbeatInterval, (_) {
        RoomParticipantService.heartbeat(widget.room.id, _sessionId);
      });
      _sweepSub = _participantsStream.listen((participants) {
        RoomParticipantService.sweepStaleParticipants(widget.room.id, participants);
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
    _toolbarScrollController.dispose();
    _roomSub?.cancel();
    _heartbeatTimer?.cancel();
    _sweepSub?.cancel();
    if (widget.room.id.isNotEmpty) {
      // Fire-and-forget: the screen is already closing, nothing left to
      // await into. RoomParticipantService.leave swallows its own errors,
      // and is a no-op if _sessionId no longer owns the doc (a fresh
      // rejoin already claimed it before this call landed).
      RoomParticipantService.leave(widget.room.id, _sessionId);
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

  /// Host-only "Leave" — distinct from End Room. If no moderator exists
  /// yet, the host must hand the stage off to one of the current speakers
  /// first (see _ChooseModeratorSheet); once a moderator is in place (or
  /// there's genuinely no one to hand off to), leaving just pops the
  /// screen — dispose() already does the actual RoomParticipantService.leave.
  Future<void> _leave(List<RoomParticipant> participants) async {
    final hasModerator = participants.any((p) => p.isModerator);
    if (hasModerator) {
      Navigator.of(context).pop();
      return;
    }

    final stageCandidates = participants.where((p) => p.role == 'speaker').toList();
    if (stageCandidates.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave without a moderator?'),
          content: const Text(
            "There's no one else on stage to hand the room to. You can still "
            'leave — the room will stay open without a moderator until '
            'someone can end it.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Leave anyway', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      Navigator.of(context).pop();
      return;
    }

    final chosen = await showModalBottomSheet<RoomParticipant>(
      context: context,
      backgroundColor: bubble,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ChooseModeratorSheet(candidates: stageCandidates),
    );
    if (chosen == null || !mounted) return;

    try {
      await RoomParticipantService.promoteToModerator(roomId: widget.room.id, uid: chosen.uid);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not assign moderator: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  // Every room is public, so anyone on stage — host, moderator, or plain
  // speaker — may share it; only queued listeners (not yet seated) can't.
  bool _canShare(RoomParticipant? me) {
    if (me == null) return false;
    return me.isSeated;
  }

  void _openRoomOptions(RoomParticipant? me, List<RoomParticipant> participants) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _RoomOptionsSheet(
        canShare: _canShare(me),
        onShare: () {
          Navigator.of(sheetContext).pop();
          RoomShareService.shareRoom(widget.room);
        },
        onMinimize: () {
          // Close the sheet first, then pop the detail screen back to the
          // feed WITHOUT calling leave() — the session stays alive in the
          // background (heartbeat keeps ticking via the Timer we already
          // started) so the user can rejoin from the room card.
          Navigator.of(sheetContext).pop();
          if (mounted) Navigator.of(context).pop();
        },
        onLeave: () {
          Navigator.of(sheetContext).pop();
          if (_isHost) {
            _leave(participants);
          } else if (mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  /// Host/moderator-only "Add images" — picks a photo, uploads it via the
  /// same hello-backend endpoint EditProfileScreen uses for avatars (see
  /// StorageService.uploadWhiteboardImage), then adds it to the board.
  Future<void> _addWhiteboardImage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (picked == null) return;

    setState(() => _addingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await StorageService.uploadWhiteboardImage(uid, bytes);
      await WhiteboardService.addImage(roomId: widget.room.id, imageUrl: url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add image: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _addingImage = false);
    }
  }

  /// Host/moderator-only "Type text" — also reused for tapping an existing
  /// text item on the board to edit it in place (pass [existing]).
  Future<void> _addOrEditText({WhiteboardItem? existing}) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bubble,
        title: Text(
          existing == null ? 'Add text to the board' : 'Edit text',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Say something...',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7B68F4))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(existing == null ? 'Add' : 'Save', style: const TextStyle(color: Color(0xFF7B68F4))),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty || !mounted) return;

    try {
      if (existing == null) {
        await WhiteboardService.addText(roomId: widget.room.id, text: result);
      } else {
        await WhiteboardService.editText(roomId: widget.room.id, itemId: existing.id, text: result);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save text: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _removeWhiteboardItem(WhiteboardItem item) async {
    try {
      await WhiteboardService.removeItem(roomId: widget.room.id, itemId: item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove item: ${e.toString().replaceFirst('Exception: ', '')}')),
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
                      // The chips below vary with role (board tools, Invite,
                      // End Room, Leave) and easily outnumber what a narrow
                      // phone width can fit on one line — a plain Row here
                      // used to overflow, clipping "End Room" and pushing the
                      // "..." menu off-screen entirely (with the classic
                      // yellow/black overflow stripes in debug builds).
                      // Scrolling this middle section instead of the whole
                      // toolbar keeps back and "..." always reachable on
                      // every device, with everything else reachable via an
                      // always-visible scrollbar rather than requiring users
                      // to discover an invisible swipe area. On desktop/web
                      // this only actually works with AppScrollBehavior (see
                      // main.dart) enabling mouse/trackpad drag — without it
                      // a scrollable like this silently ignores mouse drags,
                      // which is what made options look "missing" rather
                      // than just off-screen on non-touch devices.
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: Scrollbar(
                            controller: _toolbarScrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            thickness: 3,
                            radius: const Radius.circular(8),
                            child: SingleChildScrollView(
                              controller: _toolbarScrollController,
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.only(right: 10, bottom: 6),
                              child: Row(
                                children: [
                                  if (me?.canModerate ?? false) ...[
                                    _addingImage
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                          )
                                        : _actionChip(
                                            'Add images',
                                            Icons.add_photo_alternate_outlined,
                                            onTap: _addWhiteboardImage,
                                          ),
                                    const SizedBox(width: 8),
                                    _actionChip(
                                      'Type text',
                                      Icons.text_fields_rounded,
                                      onTap: () => _addOrEditText(),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (_isHost) ...[
                                    _actionChip('Invite', Icons.person_add_alt_1_rounded, onTap: _openInviteSheet),
                                    const SizedBox(width: 8),
                                  ],
                                  if (me?.canModerate ?? false) ...[
                                    _ending
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                                          )
                                        : _actionChip('End Room', Icons.call_end_rounded, onTap: _confirmEndRoom),
                                    const SizedBox(width: 8),
                                  ],
                                  if (_isHost)
                                    _actionChip('Leave', Icons.logout_rounded, onTap: () => _leave(participants)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _openRoomOptions(me, participants),
                        child: Container(
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
                              // Whiteboard content — renders nothing (keeping
                              // today's plain empty look) until the host or a
                              // moderator adds an image or text note.
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: StreamBuilder<List<WhiteboardItem>>(
                                    stream: _whiteboardStream,
                                    builder: (context, wbSnapshot) {
                                      final items = wbSnapshot.data ?? const <WhiteboardItem>[];
                                      if (items.isEmpty) return const SizedBox.shrink();
                                      final canEdit = me?.canModerate ?? false;
                                      return ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.all(10),
                                        itemCount: items.length,
                                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                                        itemBuilder: (context, i) => _WhiteboardTile(
                                          item: items[i],
                                          canEdit: canEdit,
                                          onEditText: () => _addOrEditText(existing: items[i]),
                                          onRemove: () => _removeWhiteboardItem(items[i]),
                                        ),
                                      );
                                    },
                                  ),
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
                                // 0.85 gives each cell enough height for the
                                // 56 px avatar + 4 px gap + ~14 px name label
                                // without overflowing on narrow screens.
                                childAspectRatio: 0.85,
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
                                        canModerate: me?.canModerate ?? false,
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
                                            // Role badge — opposite corner from
                                            // the on-air mic badge above. Plain
                                            // speakers get no badge (their
                                            // default look already reads as
                                            // "just a participant").
                                            if (speaker.isHost || speaker.isModerator)
                                              Positioned(
                                                left: -2,
                                                top: -2,
                                                child: Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    color: speaker.isHost
                                                        ? const Color(0xFFE8A23C)
                                                        : const Color(0xFF7B68F4),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    speaker.isHost ? Icons.star_rounded : Icons.shield_rounded,
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

/// Bottom sheet the host picks a moderator from before leaving — see
/// _VoiceRoomDetailScreenState._leave. [candidates] is the live stage
/// roster (speakers only, host excluded), passed in directly since it's
/// already in hand from the same StreamBuilder frame — no separate fetch
/// needed here.
/// The green "…" menu's bottom sheet — see
/// _VoiceRoomDetailScreenState._openRoomOptions. Deliberately scoped to
/// just Share and Leave for now (not the full reference design's
/// "Minimize the room" / "Close", which have no defined behavior in this
/// app yet) — reuses the room's existing Leave semantics rather than
/// inventing new ones.
class _RoomOptionsSheet extends StatelessWidget {
  final bool canShare;
  final VoidCallback onShare;
  final VoidCallback onMinimize;
  final VoidCallback onLeave;
  const _RoomOptionsSheet({
    required this.canShare,
    required this.onShare,
    required this.onMinimize,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _VoiceRoomDetailScreenState.bubble,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OptionRow(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    enabled: canShare,
                    disabledHint: 'Only the host, moderators, and staged speakers can share this room.',
                    onTap: onShare,
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  _OptionRow(
                    icon: Icons.minimize_rounded,
                    label: 'Minimize the room',
                    enabled: true,
                    onTap: onMinimize,
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  _OptionRow(
                    icon: Icons.logout_rounded,
                    label: 'Leave',
                    enabled: true,
                    onTap: onLeave,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B68F4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final String? disabledHint;
  final VoidCallback onTap;
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.enabled,
    this.disabledHint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white24,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: !enabled && disabledHint != null
          ? Text(disabledHint!, style: const TextStyle(color: Colors.white38, fontSize: 11.5))
          : null,
      onTap: enabled ? onTap : null,
    );
  }
}

class _ChooseModeratorSheet extends StatelessWidget {
  final List<RoomParticipant> candidates;
  const _ChooseModeratorSheet({required this.candidates});

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
              'Choose a moderator before you leave',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "They'll be able to manage the stage and end the room after you leave.",
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 320,
              child: ListView.separated(
                itemCount: candidates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) {
                  final p = candidates[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AppAvatar(seed: p.uid.isNotEmpty ? p.uid : p.name, size: 40, imageUrl: p.avatarUrl),
                    title: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).pop(p),
                      child: const Text('Make Moderator', style: TextStyle(color: Color(0xFF7B68F4))),
                    ),
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

/// One image or text item on the stage card's whiteboard row. Only
/// host/moderator (`canEdit`) get the remove button and can tap a text
/// item to edit it — everyone else just sees the content.
class _WhiteboardTile extends StatelessWidget {
  final WhiteboardItem item;
  final bool canEdit;
  final VoidCallback onEditText;
  final VoidCallback onRemove;
  const _WhiteboardTile({
    required this.item,
    required this.canEdit,
    required this.onEditText,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final content = item.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              item.imageUrl,
              width: 140,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 140,
                color: Colors.white12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
              ),
            ),
          )
        : GestureDetector(
            onTap: canEdit ? onEditText : null,
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                item.text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          );

    if (!canEdit) return content;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        Positioned(
          right: -4,
          top: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 13, color: Colors.white70),
            ),
          ),
        ),
      ],
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
                  enabled: isSeated,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: isSeated ? 'Comments...' : 'Raise your hand to join the stage and chat',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
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
