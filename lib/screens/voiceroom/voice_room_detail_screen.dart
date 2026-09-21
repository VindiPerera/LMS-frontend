import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/room_participant.dart';
import '../../models/voiceroom.dart';
import '../../models/whiteboard_item.dart';
import '../../services/room_participant_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_room_service.dart';
import '../../services/voice_room_session_controller.dart';
import '../../services/whiteboard_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/dark_action_sheet.dart';
import '../../widgets/whiteboard_canvas.dart';
import 'expanded_whiteboard_screen.dart';
import 'raised_hands_sheet.dart';
import 'room_profile_sheet.dart';
import 'share_room_sheet.dart';
import 'whiteboard_options_sheets.dart';

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
  // Drives the live comment feed so new messages auto-scroll to the bottom
  // and users can also freely scroll back up through history. Disposed in
  // dispose() alongside every other controller on this screen.
  final _commentScrollController = ScrollController();
  // Same auto-scroll-to-newest role as _commentScrollController above, for
  // the captions panel's own line list.
  final _subtitlesScrollController = ScrollController();
  bool _subtitlesOn = false;
  bool _ending = false;
  bool _addingImage = false;
  // Set right before popping from "Minimize the room" — tells dispose() the
  // session was handed off to VoiceRoomSessionController rather than ended,
  // so it must not call RoomParticipantService.leave.
  bool _minimizedHandoff = false;

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
      RoomParticipantService.streamComments(widget.room.id);
  late final Stream<List<SubtitleLine>> _subtitlesStream =
      RoomParticipantService.streamSubtitles(widget.room.id);
  // asBroadcastStream() for the same reason as _participantsStream above:
  // both the stage card's StreamBuilder AND the expanded full-screen view
  // (and the plain _whiteboardSub cache below) need their own listener on
  // this same stream.
  late final Stream<List<WhiteboardItem>> _whiteboardStream =
      WhiteboardService.streamItems(widget.room.id).asBroadcastStream();

  // A plain cache of the board's current items, kept up to date via
  // _whiteboardSub below — used by the "add image"/"add text"/"bring to
  // front"/"send to back" actions, which need to know what's already on
  // the board (to place a new item somewhere free, or to compute the new
  // top/bottom zIndex) without an extra Firestore read of their own.
  List<WhiteboardItem> _whiteboardItems = const [];
  StreamSubscription<List<WhiteboardItem>>? _whiteboardSub;

  // Watches the signed-in user's own role so a listener who gets seated by
  // the host/moderator — RoomParticipantService.acceptRaisedHand (they
  // asked first) or acceptStageInvite (the host asked them first) — gets a
  // clear notice of it. Every path that can turn a listener into a speaker
  // now always goes through the host/moderator (see setHandRaised's doc
  // comment for why raising a hand no longer claims a seat by itself), so
  // this notice is always the right call for that transition — there's no
  // "did I do this to myself?" case left to distinguish.
  String? _lastKnownRole;
  StreamSubscription<List<RoomParticipant>>? _roleWatchSub;

  // Streams the signed-in user's own moderatorInvitePending flag from their
  // participant doc — set by the host when they send an invitation.
  StreamSubscription<bool>? _moderatorInviteSub;
  // Guards against showing the Accept/Ignore dialog more than once if the
  // stream re-emits before the user has dismissed the first one.
  bool _pendingInviteDialog = false;

  // Same idea as the two fields above, for a host/moderator's stage invite
  // (room_profile_sheet.dart's "Invite" button) rather than a moderator
  // invite — kept as its own independent stream/guard/dialog rather than
  // merged into the moderator one, since both could in principle be pending
  // for the same person at once and each needs its own Accept/Ignore.
  StreamSubscription<bool>? _stageInviteSub;
  bool _pendingStageInviteDialog = false;

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
        // A kickParticipant ban still within its 24h window — see
        // RoomParticipantService.join's pre-check and firestore.rules'
        // isBanned(), the actual enforcement this message is just fronting
        // for. Distinct, specific copy (with the remaining time) rather
        // than the generic "no access" case below.
        if (e is RoomBanException) {
          _bounceWithMessage(e.toString());
          return;
        }
        // Every room this app creates today is public and joinable by any
        // signed-in user, so firestore.rules should never actually reject
        // this — but it still can for a room document that predates that
        // (a restricted audience from before rooms went public-only) or one
        // whose audience was otherwise revoked. Without this, the screen
        // would otherwise just sit there looking joined while silently
        // having no seat, no roster write, nothing.
        final denied = e is FirebaseException && e.code == 'permission-denied';
        if (!denied) return;
        _bounceWithMessage("You don't have access to this room.");
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
      _whiteboardSub = _whiteboardStream.listen((items) {
        // setState so _whiteboardItems is up-to-date in the widget state —
        // the StreamBuilder's initialData reads this field on every rebuild,
        // so without setState the canvas would show stale (or empty) items
        // the moment it gets re-mounted after the user scrolls away and back.
        if (mounted) {
          setState(() => _whiteboardItems = items);
        } else {
          _whiteboardItems = items;
        }
      });
      // Watch this user's own moderatorInvitePending flag (stored on their
      // participant doc). The host sets it when they pick someone from the Add
      // Moderator picker; no new Firestore rules required since the host can
      // already write any participant doc, and self-writes are also allowed.
      final selfUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (!_isHost && selfUid.isNotEmpty) {
        _moderatorInviteSub = RoomParticipantService.streamModeratorInvitePending(
          widget.room.id,
          selfUid,
        ).listen((pending) {
          if (!mounted || _pendingInviteDialog) return;
          if (pending) _showModeratorInviteDialog(selfUid);
        });
        // Same pattern, for a host/moderator's stage invite — see
        // room_profile_sheet.dart's "Invite" button.
        _stageInviteSub = RoomParticipantService.streamStageInvitePending(
          widget.room.id,
          selfUid,
        ).listen((pending) {
          if (!mounted || _pendingStageInviteDialog) return;
          if (pending) _showStageInviteDialog(selfUid);
        });
      }
      _roleWatchSub = _participantsStream.listen((participants) {
        final newRole = _findMe(participants)?.role;
        if (_lastKnownRole == 'listener' && newRole == 'speaker') {
          _showInvitedToStageNotice();
        } else if (!_isHost && _lastKnownRole != null && newRole == null) {
          // We were present a moment ago and now aren't — the only way
          // that happens while this screen is open and heartbeating
          // normally (so the 90s-stale sweep can't be it) is
          // RoomParticipantService.kickParticipant deleting our own doc
          // out from under us. `_lastKnownRole != null` guards against
          // misreading "join() just hasn't landed yet" on the very first
          // snapshot or two as a kick.
          //
          // `!_isHost` guards against a real (if rare) false positive: the
          // host can never actually be kicked — room_profile_sheet.dart's
          // "Kick Out" always requires the target not be yourself, and a
          // moderator additionally can't target the host — so for the host
          // this branch can only ever mean a transient gap in this stream
          // (e.g. a rejoin's fresh doc not yet reflected in the
          // orderBy('joinedAt') query, or another client's stale-sweep
          // racing our own heartbeat), never a genuine kick. Misreading
          // that as "You were removed" would wrongly close the room the
          // host is actually still hosting.
          _handleKicked();
        }
        _lastKnownRole = newRole;
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
    _commentScrollController.dispose();
    _subtitlesScrollController.dispose();
    _roomSub?.cancel();
    _heartbeatTimer?.cancel();
    _sweepSub?.cancel();
    _whiteboardSub?.cancel();
    _roleWatchSub?.cancel();
    _moderatorInviteSub?.cancel();
    _stageInviteSub?.cancel();
    if (widget.room.id.isNotEmpty && !_minimizedHandoff) {
      // Fire-and-forget: the screen is already closing, nothing left to
      // await into. RoomParticipantService.leave swallows its own errors,
      // and is a no-op if _sessionId no longer owns the doc (a fresh
      // rejoin already claimed it before this call landed). Skipped when
      // minimized — VoiceRoomSessionController now owns this session's
      // presence instead of it ending here.
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
  // shouldn't bump you out of seat 0), then moderators, then other speakers
  // by join order, padded with empty seats out to the grid's usual size.
  // Never truncated, so a rare race in acceptRaisedHand/acceptStageInvite
  // can add an extra row rather than ever silently dropping someone who's
  // actually on stage.
  // Moderators were previously omitted because the filter only checked
  // role == 'speaker'; they now slot in between host and speakers so their
  // shield badge is always visible.
  List<RoomParticipant> _buildSeats(List<RoomParticipant> participants) {
    final host = participants.where((p) => p.isHost);
    final moderators = participants.where((p) => p.isModerator);
    final otherSpeakers = participants.where((p) => p.role == 'speaker');
    final seats = [...host, ...moderators, ...otherSpeakers];
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

  /// Host-only "Leave" — distinct from End Room.
  /// If a moderator is already assigned, leaves immediately.
  /// Otherwise shows the "Add Moderator Reminder" dialog (Screenshot 1).
  Future<void> _leave(List<RoomParticipant> participants) async {
    final hasModerator = participants.any((p) => p.isModerator && !p.isHost);
    if (hasModerator) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Show the reminder dialog matching Screenshot 1.
    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Moderator Reminder',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'There is no moderator in the current room.'
                ' The room will close when you leave.'
                ' You can add a moderator now.',
                style: TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop('set'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B68F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Set moderators',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('close'),
                child: const Text(
                  'Close',
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'set') {
      // Open the moderator panel (Screenshot 2). Pass the current
      // participants snapshot so the panel knows who is on stage.
      await _showModeratorPanel(participants);
      return; // host stays in the room after managing moderators
    }
    // 'close' or dialog dismissed — leave without assigning
    if (mounted) Navigator.of(context).pop();
  }

  /// Shows the Moderator management panel (Screenshot 2).
  /// Displays the current moderator (if any) with Add/Remove buttons.
  Future<void> _showModeratorPanel(List<RoomParticipant> participants) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _ModeratorPanelSheet(
        participants: participants,
        roomId: widget.room.id,
        onAddTap: () async {
          Navigator.of(ctx).pop(); // close panel first
          await _showAddModeratorPicker(participants);
        },
        onRemoveTap: (moderator) async {
          try {
            await RoomParticipantService.demoteModeratorToSpeaker(
              roomId: widget.room.id,
              uid: moderator.uid,
            );
            // Also cancel any pending invite for that uid.
            await VoiceRoomService.deleteModeratorInvite(widget.room.id, moderator.uid);
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${moderator.name} is no longer the moderator.'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not remove moderator: ${e.toString().replaceFirst('Exception: ', '')}')),
              );
            }
          }
        },
      ),
    );
  }

  /// Shows the Add Moderator full-screen picker (Screenshot 3).
  /// Lists stage speakers (not the host, not an existing moderator).
  /// Single-select; tapping OK sends the invite.
  Future<void> _showAddModeratorPicker(List<RoomParticipant> participants) async {
    if (!mounted) return;
    final candidates = participants
        .where((p) => p.role == 'speaker')
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No speakers on stage to invite as moderator.')),
      );
      return;
    }

    RoomParticipant? chosen;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddModeratorDialog(
        candidates: candidates,
        onChosen: (p) => chosen = p,
      ),
    );
    if (confirmed != true || chosen == null || !mounted) return;

    try {
      await RoomParticipantService.sendModeratorInvite(
        roomId: widget.room.id,
        uid: chosen!.uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moderator invitation sent to ${chosen!.name}.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send invitation: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  /// Shown to the invitee when the host sends them a moderator invitation.
  /// The invite doc is streamed by _moderatorInviteSub — this fires when
  /// status == 'pending'. [selfUid] is the signed-in user's uid (used to
  /// call promoteToModerator/deleteModeratorInvite).
  void _showModeratorInviteDialog(String selfUid) {
    if (!mounted || _pendingInviteDialog) return;
    _pendingInviteDialog = true;
    // Set right before either button pops this dialog itself, so
    // whenComplete below (a catch-all for dismissal some OTHER way, e.g.
    // the system back gesture — barrierDismissible only blocks tapping
    // outside, not that) knows to leave _pendingInviteDialog alone: those
    // two buttons' own `finally` blocks are what reset it once their
    // Firestore write has actually finished, not the moment the dialog
    // itself closes (see either button's onPressed for why that distinction
    // matters).
    var closedByButton = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFF7B68F4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                "You've been invited as Moderator",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'The host has selected you to moderate this room.'
                ' You can manage the stage, mute speakers, and keep the session running.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        closedByButton = true;
                        Navigator.of(ctx).pop();
                        try {
                          // Self-write: clear the flag from own participant doc.
                          // No host permission needed — participants can update
                          // non-role fields on their own doc (Firestore rules).
                          await RoomParticipantService.clearModeratorInvitePending(
                            widget.room.id, selfUid);
                        } finally {
                          // Only now — not the moment the dialog pops (see
                          // this doc's own history: that used to reset the
                          // guard immediately via showDialog's
                          // .whenComplete, which raced with this very
                          // write and could pop the SAME dialog right back
                          // open before the clear had actually landed).
                          _pendingInviteDialog = false;
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      child: const Text('Ignore', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        closedByButton = true;
                        Navigator.of(ctx).pop();
                        try {
                          await RoomParticipantService.promoteToModerator(
                            roomId: widget.room.id, uid: selfUid);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("You are now the moderator 🛡️"),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not accept: ${e.toString().replaceFirst('Exception: ', '')}')),
                            );
                          }
                        } finally {
                          // Not reset until promoteToModerator's whole
                          // sequence (role update -> moderatorUid persist ->
                          // clear moderatorInvitePending) has actually
                          // finished — see the Ignore button's matching
                          // comment for why resetting this the moment the
                          // dialog pops (the old behavior) was the actual
                          // bug: the role-update write alone already
                          // touches this same participant doc and would
                          // trigger a fresh "still pending" snapshot before
                          // the flag was really cleared, popping this exact
                          // dialog right back open.
                          _pendingInviteDialog = false;
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B68F4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        elevation: 0,
                      ),
                      child: const Text('Accept', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      // Only a dismissal neither button caused (system back gesture) needs
      // handling here — Accept/Ignore already reset this themselves, once
      // their own write actually finished.
      if (!closedByButton) _pendingInviteDialog = false;
    });
  }

  /// Shown to the invitee when the host/moderator sends them a stage
  /// invite (room_profile_sheet.dart's "Invite" button) — same shape as
  /// _showModeratorInviteDialog just above (including why
  /// _pendingStageInviteDialog only resets once each button's own write has
  /// actually finished, not the moment the dialog pops), just with
  /// different copy/icon and calling acceptStageInvite/declineStageInvite
  /// instead of the moderator equivalents.
  void _showStageInviteDialog(String selfUid) {
    if (!mounted || _pendingStageInviteDialog) return;
    _pendingStageInviteDialog = true;
    var closedByButton = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFF7B68F4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                "You've been invited to speak!",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'The host would like you to join the stage. Accept to take a seat and start talking.',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        closedByButton = true;
                        Navigator.of(ctx).pop();
                        try {
                          await RoomParticipantService.declineStageInvite(widget.room.id);
                        } finally {
                          _pendingStageInviteDialog = false;
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      child: const Text('Ignore', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        closedByButton = true;
                        Navigator.of(ctx).pop();
                        try {
                          await RoomParticipantService.acceptStageInvite(widget.room.id);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not join: ${e.toString().replaceFirst('Exception: ', '')}')),
                            );
                          }
                        } finally {
                          _pendingStageInviteDialog = false;
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B68F4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        elevation: 0,
                      ),
                      child: const Text('Accept', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (!closedByButton) _pendingStageInviteDialog = false;
    });
  }

  // Every room is public — anyone who reached this screen at all (host or
  // audience) may share it, so this doesn't gate on `me`/the live
  // participants stream: right after RoomParticipantService.join() writes
  // our own doc, streamParticipants' orderBy('joinedAt') query can take a
  // moment to actually reflect it (a pending serverTimestamp write isn't
  // ordered until the server acks it), so `_findMe(participants)` briefly
  // returns null even though we're genuinely in the room — which used to
  // leave Share stuck disabled if the "…" menu was opened right away.
  bool _canShare() => widget.room.id.isNotEmpty;

  void _openRoomOptions(RoomParticipant? me, List<RoomParticipant> participants) {
    // `_isHost` (derived straight from widget.room.hostId, not the live
    // stream) covers the same race as above for the common case — a host
    // opening the menu right after creating/reopening their own room, before
    // their own participant doc has shown up in `participants` yet, should
    // still see Close. A plain moderator has no such stream-independent
    // signal, so that case still depends on `me`.
    final canClose = _isHost || (me?.canModerate ?? false);
    showDarkActionSheet(
      context,
      items: [
        DarkActionItem(
          label: 'Share',
          enabled: _canShare(),
          onTap: () => showShareRoomSheet(context, room: widget.room),
        ),
        DarkActionItem(
          label: 'Minimize the room',
          onTap: () {
            // Hand presence off to VoiceRoomSessionController — it starts
            // its own heartbeat/room-ended watch so the session survives
            // this screen's dispose() — then show the floating mini window
            // and pop back to wherever the user was.
            VoiceRoomSessionController.instance.minimize(
              room: widget.room,
              sessionId: _sessionId,
            );
            _minimizedHandoff = true;
            if (mounted) Navigator.of(context).pop();
          },
        ),
        DarkActionItem(
          label: 'Leave',
          onTap: () {
            if (_isHost) {
              _leave(participants);
            } else if (mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        // "Close" — the old toolbar's "End Room", relabeled and moved in
        // here (see the toolbar Row's own comment). Same permission gate
        // (host/moderator) and same underlying action (_confirmEndRoom's
        // own confirm dialog + VoiceRoomService.endRoom) as before.
        if (canClose)
          DarkActionItem(
            label: 'Close',
            color: const Color(0xFFFF4757),
            onTap: _confirmEndRoom,
          ),
      ],
    );
  }

  /// Host/moderator-only "Add images" — picks a photo, uploads it via the
  /// same hello-backend endpoint EditProfileScreen uses for avatars (see
  /// StorageService.uploadWhiteboardImage), then adds it to the board sized
  /// to match its own proportions (see WhiteboardService.addImage) and
  /// placed somewhere that doesn't already have something on it.
  Future<void> _addWhiteboardImage() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 85);
    if (picked == null) return;

    setState(() => _addingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final aspectRatio = await _decodeAspectRatio(bytes);
      final url = await StorageService.uploadWhiteboardImage(uid, bytes);
      await WhiteboardService.addImage(
        roomId: widget.room.id,
        imageUrl: url,
        aspectRatio: aspectRatio,
        existingItems: _whiteboardItems,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add image: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _addingImage = false);
    }
  }

  /// The picked image's own width/height ratio, so its board tile can be
  /// resized later without distorting it (see WhiteboardCanvas's resize
  /// handle). Falls back to a square ratio if decoding ever fails — the
  /// image itself still adds fine, it would just resize freely instead of
  /// aspect-locked.
  Future<double> _decodeAspectRatio(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return ratio > 0 ? ratio : 1;
    } catch (_) {
      return 1;
    }
  }

  /// Host/moderator-only "Type text" — opens the same composer used to
  /// edit an existing text item (see _openWhiteboardItemOptions), just
  /// with no starting content/style.
  Future<void> _openTextComposerForNew() {
    return showTextComposerSheet(
      context,
      onSave: (draft) async {
        try {
          await WhiteboardService.addText(
            roomId: widget.room.id,
            text: draft.text,
            existingItems: _whiteboardItems,
            fontSize: draft.fontSize,
            colorHex: draft.colorHex,
            bold: draft.bold,
            textAlign: draft.textAlign,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add text: ${e.toString().replaceFirst('Exception: ', '')}')),
          );
        }
      },
    );
  }

  /// The "⋮" handle on a selected board item (see WhiteboardCanvas) — text
  /// gets the full composer (wording + style + z-order + delete); images
  /// get a lighter sheet (rotate + z-order + delete), since there's no
  /// wording or styling to edit on a photo.
  void _openWhiteboardItemOptions(WhiteboardItem item) {
    if (item.isText) {
      showTextComposerSheet(
        context,
        existing: item,
        onSave: (draft) async {
          try {
            await WhiteboardService.saveText(
              roomId: widget.room.id,
              itemId: item.id,
              text: draft.text,
              fontSize: draft.fontSize,
              colorHex: draft.colorHex,
              bold: draft.bold,
              textAlign: draft.textAlign,
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save text: ${e.toString().replaceFirst('Exception: ', '')}')),
            );
          }
        },
        onDelete: () => _removeWhiteboardItem(item),
        onBringToFront: () => _bringWhiteboardItemToFront(item),
        onSendToBack: () => _sendWhiteboardItemToBack(item),
      );
    } else {
      showImageOptionsSheet(
        context,
        onRotate: () => _rotateWhiteboardImage(item),
        onBringToFront: () => _bringWhiteboardItemToFront(item),
        onSendToBack: () => _sendWhiteboardItemToBack(item),
        onDelete: () => _removeWhiteboardItem(item),
      );
    }
  }

  /// Commits a move or resize once the user releases the drag/resize
  /// handle — see WhiteboardCanvas's doc comment for why this is the only
  /// point a transform gets written, not every frame while dragging.
  Future<void> _commitWhiteboardTransform(WhiteboardItem item) async {
    try {
      await WhiteboardService.updateTransform(
        roomId: widget.room.id,
        itemId: item.id,
        x: item.x,
        y: item.y,
        width: item.width,
        height: item.height,
        rotation: item.isImage ? item.rotation : null,
        fontSize: item.isText ? item.fontSize : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move that: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _rotateWhiteboardImage(WhiteboardItem item) async {
    try {
      await WhiteboardService.updateTransform(
        roomId: widget.room.id,
        itemId: item.id,
        x: item.x,
        y: item.y,
        width: item.width,
        height: item.height,
        rotation: (item.rotation + 90) % 360,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rotate that: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _bringWhiteboardItemToFront(WhiteboardItem item) async {
    try {
      await WhiteboardService.bringToFront(roomId: widget.room.id, itemId: item.id, existingItems: _whiteboardItems);
    } catch (_) {
      // Non-critical — worst case it just stays at its current layer.
    }
  }

  Future<void> _sendWhiteboardItemToBack(WhiteboardItem item) async {
    try {
      await WhiteboardService.sendToBack(roomId: widget.room.id, itemId: item.id, existingItems: _whiteboardItems);
    } catch (_) {
      // Non-critical — worst case it just stays at its current layer.
    }
  }

  /// Opens the board full-screen (see WhiteboardGeometry — same aspect
  /// ratio as the inline card, just bigger) for more precise dragging and
  /// resizing than the small stage-card preview allows, especially on a
  /// phone. Read-only for anyone who isn't host/moderator, same as inline.
  void _openExpandedWhiteboard(bool canEdit) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpandedWhiteboardScreen(
          roomId: widget.room.id,
          canEdit: canEdit,
          itemsStream: _whiteboardStream,
          // Seed with the current cached items so the full-screen view
          // renders immediately — see ExpandedWhiteboardScreen.initialItems.
          initialItems: _whiteboardItems,
          onTransformEnd: _commitWhiteboardTransform,
          onOpenOptions: _openWhiteboardItemOptions,
          onQuickDelete: _removeWhiteboardItem,
        ),
      ),
    );
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

  Future<void> _sendComment() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    try {
      await RoomParticipantService.sendComment(roomId: widget.room.id, text: text);
    } catch (e) {
      if (!mounted) return;
      _controller.text = text;
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

  /// Tapping an empty seat or the composer's raise-hand button — both raise
  /// (or, tapped again while already waiting, lower) the caller's own hand
  /// rather than instantly claiming a seat. A host/moderator still has to
  /// actually seat them (see the Raised Hands sheet's Accept), even when a
  /// seat happens to be open right now — see
  /// RoomParticipantService.setHandRaised's doc comment for why that's
  /// deliberate. No _expectingOwnPromotion bookkeeping needed here (unlike
  /// the old instant-seat version): raising a hand never changes `role`
  /// itself, so _roleWatchSub's "was I just invited up?" notice fires
  /// correctly and only once the host actually accepts — exactly the
  /// moment that notice is for.
  Future<void> _raiseHand(RoomParticipant? me) async {
    if (me != null && me.isSeated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're already on stage.")),
      );
      return;
    }
    final alreadyRaised = me?.handRaised ?? false;
    try {
      await RoomParticipantService.setHandRaised(widget.room.id, !alreadyRaised);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyRaised ? 'Hand lowered.' : 'Hand raised — waiting for the host to invite you up.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// The Raised Hands badge — host/moderator reviewing the queue.
  void _openRaisedHandsSheet() {
    showRaisedHandsSheet(context, roomId: widget.room.id);
  }

  /// Shown to a listener the moment the host/moderator seats them —
  /// RoomParticipantService.acceptRaisedHand or .acceptStageInvite — see
  /// _roleWatchSub's doc comment. Same floating-snackbar look as the
  /// mic-etiquette reminder
  /// above (bubble bg, rounded shape, icon + message) for a consistent
  /// "something worth noticing just happened" moment in this screen.
  void _showInvitedToStageNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
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
              Icon(Icons.mic_rounded, color: Color(0xFF7B68F4), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You're invited to speak! Say hi to everyone 🎤",
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Pops this screen (once the first frame after it's actually attached —
  /// this can fire from initState, before the Scaffold/ScaffoldMessenger
  /// above it is reliably available yet) with an explanatory snackbar.
  /// Shared by every "couldn't actually join this room" case — see
  /// initState's join().catchError.
  void _bounceWithMessage(String message) {
    // No addPostFrameCallback here (unlike the justCreated mic-reminder
    // snackbar above, which needs one because it runs synchronously inside
    // initState, before the very first frame): this always fires from an
    // async join().catchError callback, well after initState has returned
    // and at least one frame has already built, so context is already
    // attached to a live Scaffold/Navigator by the time this runs.
    // Wrapping it in addPostFrameCallback here was the actual cause of a
    // real bug — with no frame already scheduled at that point, the
    // callback just sat queued until some unrelated interaction (e.g.
    // scrolling) happened to trigger the next one, so the room stayed
    // open, fully interactive, until then instead of closing immediately.
    if (!mounted || _ending) return;
    _ending = true;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Fires the moment this screen notices its OWN participant doc has
  /// disappeared — see _roleWatchSub's doc comment for why that only ever
  /// means RoomParticipantService.kickParticipant (room_profile_sheet.
  /// dart's "Kick Out"). `_ending` doubles as the same "already handling a
  /// screen-closing event" guard _roomSub's room-ended listener uses, so
  /// the two can never both try to pop this screen.
  void _handleKicked() {
    if (!mounted || _ending) return;
    _ending = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('You were removed from this room.')),
    );
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
                                      onTap: _openTextComposerForNew,
                                    ),
                                  ],
                                  // Invite / End Room / Leave used to live
                                  // here too — all three moved into the "…"
                                  // menu (see _openRoomOptions): Leave was
                                  // already duplicated there, End Room is
                                  // now that menu's "Close" row, and the
                                  // standalone friend-invite flow is fully
                                  // superseded by the Share sheet's "Share
                                  // to a Chat" (a joinable room-invite card
                                  // sent straight into a real conversation,
                                  // versus a bare push notification) and by
                                  // inviting an audience member onto the
                                  // stage directly from their profile.
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
                          aspectRatio: WhiteboardGeometry.aspectRatio,
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
                                    // Seed the builder with the already-cached
                                    // items so the canvas renders instantly when
                                    // the widget is re-mounted after the user
                                    // scrolls away and back. Without this,
                                    // broadcast streams don't replay their last
                                    // value to new subscribers, leaving the board
                                    // blank until the next Firestore event fires.
                                    initialData: _whiteboardItems,
                                    builder: (context, wbSnapshot) {
                                      final items = wbSnapshot.data ?? const <WhiteboardItem>[];
                                      final canEdit = me?.canModerate ?? false;
                                      return WhiteboardCanvas(
                                        items: items,
                                        canEdit: canEdit,
                                        onTransformEnd: _commitWhiteboardTransform,
                                        onOpenOptions: _openWhiteboardItemOptions,
                                        onQuickDelete: _removeWhiteboardItem,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              // Opens the same board full-screen, for precise
                              // dragging/resizing on a small phone card — a
                              // decorative hint (not a hit target of its own)
                              // until there's actually a board worth expanding.
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: GestureDetector(
                                  onTap: () => _openExpandedWhiteboard(me?.canModerate ?? false),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                    child: const Icon(
                                      Icons.open_in_full_rounded,
                                      color: Colors.white70,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 4,
                                // Cells only need ~74px (56px avatar + 4px
                                // gap + ~14px name label) to avoid
                                // overflowing on narrow screens — 1.05 stays
                                // comfortably above that while trimming the
                                // extra headroom 0.85 used to leave, pulling
                                // the second row of seats upward to make room
                                // for the subtitles panel below.
                                childAspectRatio: 1.05,
                              ),
                          itemCount: seats.length,
                          itemBuilder: (context, i) {
                            final speaker = seats[i];
                            return GestureDetector(
                              onTap: speaker.isEmptySeat
                                  ? () => _raiseHand(me)
                                  : () => showRoomProfileSheet(
                                        context,
                                        speaker,
                                        roomId: widget.room.id,
                                        canModerate: me?.canModerate ?? false,
                                        isHost: _isHost,
                                      ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  speaker.isEmptySeat
                                      ? Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: (me?.handRaised ?? false)
                                                ? const Color(0xFFE8A23C).withValues(alpha: 0.22)
                                                : Colors.white12,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: (me?.handRaised ?? false)
                                                  ? const Color(0xFFE8A23C)
                                                  : Colors.white38,
                                              width: 1,
                                            ),
                                          ),
                                          // Amber once the signed-in user has
                                          // raised their own hand — a plain
                                          // "you're in the queue" indicator,
                                          // not something every empty seat
                                          // shows (only ever reflects the
                                          // viewer's own state; the grid has
                                          // no per-seat "who raised" concept).
                                          child: Icon(
                                            Icons.front_hand_rounded,
                                            color: (me?.handRaised ?? false)
                                                ? const Color(0xFFE8A23C)
                                                : Colors.white38,
                                            size: 22,
                                          ),
                                        )
                                      : Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // Avatar with green border highlight
                                            // when unmuted/speaking, plain when muted.
                                            AppAvatar(
                                              seed: speaker.uid.isNotEmpty ? speaker.uid : '${speaker.name}$i',
                                              size: 56,
                                              showFlag: true,
                                              flag: speaker.flag,
                                              imageUrl: speaker.avatarUrl,
                                              borderWidth: speaker.isSpeaking ? 2.5 : 0,
                                              borderColor: const Color(0xFF3DDC97),
                                            ),
                                            // Muted badge — a small mic-off
                                            // circle centered over the middle
                                            // of the avatar, but only a
                                            // fraction of its size — not the
                                            // full-circle overlay this used
                                            // to be (which hid the photo/
                                            // initial entirely while muted),
                                            // and not pinned to the edge
                                            // either. Only shown when the
                                            // seat is occupied AND the
                                            // participant is muted.
                                            if (!speaker.isSpeaking)
                                              Positioned.fill(
                                                child: Center(
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.4),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.mic_off_rounded,
                                                      color: Colors.white,
                                                      size: 17,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            // When unmuted/speaking the green
                                            // border highlight (borderWidth above)
                                            // is the sole visual indicator —
                                            // no extra badge needed.
                                          ],
                                        ),
                                  const SizedBox(height: 4),
                                  // Name row — prefixed with a host/moderator
                                  // role icon so rank is readable without
                                  // blocking the profile picture.
                                  if (speaker.isEmptySeat)
                                    Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        if (speaker.isHost)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Icon(
                                              Icons.star_rounded,
                                              color: Color(0xFFE8A23C),
                                              size: 11,
                                            ),
                                          )
                                        else if (speaker.isModerator)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Icon(
                                              Icons.shield_rounded,
                                              color: Color(0xFF7B68F4),
                                              size: 11,
                                            ),
                                          ),
                                        Flexible(
                                          child: Text(
                                            speaker.name,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
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
                                      GestureDetector(
                                        onTap: () => showRoomProfileSheet(
                                          context,
                                          listener,
                                          roomId: widget.room.id,
                                          canModerate: me?.canModerate ?? false,
                                          isHost: _isHost,
                                        ),
                                        child: AppAvatar(
                                          seed: listener.uid.isNotEmpty ? listener.uid : listener.name,
                                          size: 32,
                                          imageUrl: listener.avatarUrl,
                                        ),
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
                      // Directly underneath the audience section, per the
                      // HelloTalk-style layout this mirrors — collapses to
                      // nothing when subtitles are off (see _Composer's new
                      // CC toggle) so it never eats space it isn't using.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: _SubtitleCaptionsPanel(
                          visible: _subtitlesOn,
                          stream: _subtitlesStream,
                          scrollController: _subtitlesScrollController,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                        child: StreamBuilder<List<BoardComment>>(
                          stream: _commentsStream,
                          builder: (context, commentsSnap) {
                            final comments = commentsSnap.data ?? const <BoardComment>[];
                            if (comments.isEmpty) return const SizedBox.shrink();

                            // Auto-scroll to the newest comment whenever
                            // the list grows. Post-frame so the ListView
                            // has already laid out the new item before we
                            // try to jump to its end.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_commentScrollController.hasClients) {
                                _commentScrollController.animateTo(
                                  _commentScrollController.position.maxScrollExtent,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              }
                            });

                            // Height is fluid: up to ~4 comment rows
                            // (~88 px) on any screen width — scales down
                            // naturally on small phones because every
                            // row uses Flexible/Expanded internally.
                            // BouncingScrollPhysics gives a native iOS
                            // feel; ClampingScrollPhysics would be fine
                            // for Android-only, but both platforms are
                            // in scope here.
                            return ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 88),
                              child: ListView.builder(
                                controller: _commentScrollController,
                                shrinkWrap: true,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: comments.length,
                                itemBuilder: (context, index) =>
                                    _CommentLine(comment: comments[index]),
                              ),
                            );
                          },
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
                  onRaiseHand: () => _raiseHand(me),
                  subtitlesOn: _subtitlesOn,
                  onToggleSubtitles: () => setState(() => _subtitlesOn = !_subtitlesOn),
                  // Only host/moderator get the Raised Hands badge in place
                  // of their own (otherwise-inert, since they're always
                  // seated already) raise-hand button — see _Composer's own
                  // doc comment for why this slot specifically.
                  raisedHandsStream: (me?.canModerate ?? false)
                      ? RoomParticipantService.streamRaisedHands(widget.room.id)
                      : null,
                  onOpenRaisedHands: _openRaisedHandsSheet,
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

// ---------------------------------------------------------------------------
// Moderator Panel — Screenshot 2
// Shows the currently-assigned moderator(s) and Add / Remove buttons.
// ---------------------------------------------------------------------------
class _ModeratorPanelSheet extends StatelessWidget {
  final List<RoomParticipant> participants;
  final String roomId;
  final VoidCallback onAddTap;
  final void Function(RoomParticipant moderator) onRemoveTap;

  const _ModeratorPanelSheet({
    required this.participants,
    required this.roomId,
    required this.onAddTap,
    required this.onRemoveTap,
  });

  @override
  Widget build(BuildContext context) {
    final moderators = participants.where((p) => p.isModerator).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Moderator',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            // Avatar strip — shows current moderators (max 1 per spec)
            if (moderators.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: moderators.map((mod) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AppAvatar(
                                seed: mod.uid.isNotEmpty ? mod.uid : mod.name,
                                size: 60,
                                imageUrl: mod.avatarUrl,
                                flag: mod.flag,
                                showFlag: mod.flag.isNotEmpty,
                                borderWidth: 2.5,
                                borderColor: const Color(0xFF7B68F4),
                              ),
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF7B68F4),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.shield_rounded,
                                    color: Colors.white,
                                    size: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            mod.name,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No moderator assigned yet.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            const SizedBox(height: 24),
            // Add / Remove action buttons
            Row(
              children: [
                // Add button — disabled once a moderator is already set
                // (one moderator at a time per spec).
                _PanelActionButton(
                  icon: Icons.add_rounded,
                  label: 'Add',
                  enabled: moderators.isEmpty,
                  onTap: moderators.isEmpty ? onAddTap : null,
                ),
                const SizedBox(width: 20),
                // Remove button — only enabled when a moderator exists.
                _PanelActionButton(
                  icon: Icons.remove_rounded,
                  label: 'Remove',
                  enabled: moderators.isNotEmpty,
                  onTap: moderators.isNotEmpty
                      ? () => onRemoveTap(moderators.first)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _PanelActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
              border: Border.all(
                color: enabled ? Colors.white24 : Colors.white12,
                width: 1.2,
              ),
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white24,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white70 : Colors.white24,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Moderator Picker — Screenshot 3
// Full-screen dark dialog with search bar + single-select radio list.
// ---------------------------------------------------------------------------
class _AddModeratorDialog extends StatefulWidget {
  final List<RoomParticipant> candidates;
  final void Function(RoomParticipant) onChosen;

  const _AddModeratorDialog({
    required this.candidates,
    required this.onChosen,
  });

  @override
  State<_AddModeratorDialog> createState() => _AddModeratorDialogState();
}

class _AddModeratorDialogState extends State<_AddModeratorDialog> {
  static const _bg = Color(0xFF0F0F1E);
  final _searchCtrl = TextEditingController();
  RoomParticipant? _selected;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RoomParticipant> get _filtered {
    if (_query.isEmpty) return widget.candidates;
    final q = _query.toLowerCase();
    return widget.candidates
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: _bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white70, size: 20),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const Expanded(
                    child: Text(
                      'Add Moderator',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: _selected != null
                        ? () {
                            widget.onChosen(_selected!);
                            Navigator.of(context).pop(true);
                          }
                        : null,
                    child: Text(
                      'OK',
                      style: TextStyle(
                        color: _selected != null
                            ? const Color(0xFF7B68F4)
                            : Colors.white30,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.white38, size: 20),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            ),
            // Candidate list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final p = _filtered[i];
                  final isSelected = _selected?.uid == p.uid;
                  return InkWell(
                    onTap: () => setState(() => _selected = p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          // Radio indicator
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF7B68F4)
                                    : Colors.white38,
                                width: 2,
                              ),
                              color: isSelected
                                  ? const Color(0xFF7B68F4)
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 14)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          AppAvatar(
                            seed: p.uid.isNotEmpty ? p.uid : p.name,
                            size: 44,
                            imageUrl: p.avatarUrl,
                            showFlag: p.flag.isNotEmpty,
                            flag: p.flag,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
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

/// The dedicated captions panel directly under the audience section (see
/// _Composer's CC toggle, which drives [visible]). Collapses to nothing
/// when subtitles are off; otherwise streams
/// RoomParticipantService.streamSubtitles and grows with content up to a
/// cap, then scrolls — same shape as the comment feed just below it.
///
/// No speech-to-text/translation pipeline exists yet, so [stream] is
/// typically empty; the panel shows a muted "Listening for captions…"
/// placeholder in that case rather than looking broken, and will start
/// rendering real lines the moment something writes to that subcollection
/// (RoomParticipantService.addSubtitleLine) — no UI change needed then.
class _SubtitleCaptionsPanel extends StatelessWidget {
  final bool visible;
  final Stream<List<SubtitleLine>> stream;
  final ScrollController scrollController;

  const _SubtitleCaptionsPanel({
    required this.visible,
    required this.stream,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: StreamBuilder<List<SubtitleLine>>(
                stream: stream,
                builder: (context, snapshot) {
                  final lines = snapshot.data ?? const <SubtitleLine>[];
                  if (lines.isEmpty) {
                    return const Text(
                      'Listening for captions…',
                      style: TextStyle(fontSize: 12, color: Colors.white38, fontStyle: FontStyle.italic),
                    );
                  }

                  // Auto-scroll to the newest line, same pattern as the
                  // comment feed's own post-frame callback below.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (scrollController.hasClients) {
                      scrollController.animateTo(
                        scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  });

                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 90),
                    child: ListView.builder(
                      controller: scrollController,
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${line.speakerName}: ',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: line.text,
                                  style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
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
          // Use senderId (uid) as the avatar seed so two users with the same
          // display name never get the same generated avatar. Falls back to
          // the display name for legacy comments that pre-date senderId.
          AppAvatar(
            seed: comment.senderId.isNotEmpty ? comment.senderId : comment.sender,
            size: 18,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              maxLines: 2,
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
  final bool subtitlesOn;
  final VoidCallback onToggleSubtitles;
  // Non-null only for a host/moderator, who's always seated already and so
  // has no use for the self raise-hand button below — this repurposes that
  // exact slot into the Raised Hands notification badge instead, rather
  // than adding a whole new spot for it. Bottom row here stays in the same
  // place regardless of how tall the seat grid above it is (unlike the
  // scrolling comment feed the badge used to sit beside), so this is also
  // the one spot in this screen guaranteed not to end up looking "too
  // high" on a narrow/tall viewport.
  final Stream<List<RoomParticipant>>? raisedHandsStream;
  final VoidCallback? onOpenRaisedHands;
  const _Composer({
    required this.controller,
    required this.me,
    required this.onSend,
    required this.onToggleMic,
    required this.onRaiseHand,
    required this.subtitlesOn,
    required this.onToggleSubtitles,
    this.raisedHandsStream,
    this.onOpenRaisedHands,
  });

  @override
  Widget build(BuildContext context) {
    final isSeated = me?.isSeated ?? false;
    final isUnmuted = isSeated && !(me?.isMuted ?? true);
    final handRaised = !isSeated && (me?.handRaised ?? false);

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
                    suffixIcon: isSeated
                        ? ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller,
                            builder: (context, value, _) {
                              if (value.text.trim().isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return IconButton(
                                icon: const Icon(Icons.send_rounded, size: 16, color: Color(0xFF4FA8FF)),
                                onPressed: onSend,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                splashRadius: 16,
                              );
                            },
                          )
                        : null,
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
          // Toggles the captions panel above the comment feed — a personal
          // viewing preference, not tied to seat/mic state, so unlike the
          // two buttons around it this one is always tappable regardless of
          // role.
          GestureDetector(
            onTap: onToggleSubtitles,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: subtitlesOn ? const Color(0xFF7B68F4) : Colors.white24,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.closed_caption_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (raisedHandsStream != null)
            RaisedHandsBadge(stream: raisedHandsStream!, onTap: onOpenRaisedHands!)
          else
            GestureDetector(
              onTap: onRaiseHand,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  // Amber while waiting (mirrors the empty-seat grid's own
                  // amber highlight for the same state) so it's obvious at a
                  // glance the request already went out — tapping it again
                  // lowers the hand.
                  color: isSeated
                      ? Colors.white24
                      : (handRaised ? const Color(0xFFE8A23C) : const Color(0xFF7B68F4)),
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
