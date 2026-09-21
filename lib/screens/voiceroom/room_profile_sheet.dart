import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/report_model.dart';
import '../../models/room_participant.dart';
import '../../models/user.dart';
import '../../services/follow_service.dart';
import '../../services/report_service.dart';
import '../../services/room_participant_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/dark_action_sheet.dart';

Future<void> showRoomProfileSheet(
  BuildContext context,
  RoomParticipant participant, {
  required String roomId,
  required bool canModerate,
  bool isHost = false,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Explicit (these already match showModalBottomSheet's own defaults,
    // but spelled out here so the intent can't silently regress): a
    // full-screen modal barrier sits behind the sheet and in front of the
    // rest of VoiceRoomDetailScreen the whole time this is open, so a tap
    // anywhere that isn't the sheet itself — the stage grid, the audience
    // row, the subtitles panel, the toolbar, plain background — hits that
    // barrier and dismisses uniformly, with no per-area wiring needed. A
    // tap on a button *inside* the sheet is safe too: it's consumed by the
    // sheet's own (topmost) hit-test region before it could ever reach the
    // barrier underneath, so an action never races its own dismissal.
    isDismissible: true,
    enableDrag: true,
    builder: (_) => RoomProfileSheet(
      participant: participant,
      roomId: roomId,
      canModerate: canModerate,
      isHost: isHost,
    ),
  );
}

class RoomProfileSheet extends StatefulWidget {
  final RoomParticipant participant;
  final String roomId;
  final bool canModerate;
  final bool isHost;
  const RoomProfileSheet({
    super.key,
    required this.participant,
    required this.roomId,
    required this.canModerate,
    this.isHost = false,
  });

  @override
  State<RoomProfileSheet> createState() => _RoomProfileSheetState();
}

class _RoomProfileSheetState extends State<RoomProfileSheet> {
  static const _bg = Color(0xFF16162E);
  static const _card = Color(0xFF1B1B3A);
  static const _pink = Color(0xFFE83E8C);
  static const _green = Color(0xFF3DDC97);

  late Timer _timer;
  late DateTime _now;

  bool get _isSelf =>
      widget.participant.uid.isNotEmpty &&
      widget.participant.uid == FirebaseAuth.instance.currentUser?.uid;

  /// Whether the signed-in viewer may act on THIS participant via the "…"
  /// menu below (mute/unmute, kick out) — mirrors firestore.rules'
  /// participants update/delete rules exactly: the host may act on anyone
  /// but themselves; a plain moderator may act on anyone except the host or
  /// another moderator. "Report" doesn't need this — it only ever writes a
  /// new `reports/{id}` doc, which isn't gated by this hierarchy at all.
  bool get _canActOnTarget {
    if (_isSelf || !widget.canModerate) return false;
    if (widget.isHost) return true;
    return !widget.participant.isHost && !widget.participant.isModerator;
  }

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// A minimal AppUser snapshot for FollowService.follow, which needs a
  /// name/avatar/flag to denormalize onto the follow edge (see
  /// FollowService's own doc comment) — RoomParticipant doesn't carry a
  /// `handle`, so that's left blank rather than guessed at.
  AppUser _participantAsAppUser() {
    final p = widget.participant;
    return AppUser(
      id: p.uid,
      name: p.name,
      handle: '',
      avatarUrl: p.avatarUrl,
      countryFlag: p.flag,
      nativeLang: p.nativeLang,
      learningLang: p.learningLang,
      gender: p.gender,
      age: p.age,
    );
  }

  /// The header Follow button's tap handler, for every state it can be in
  /// (plain Follow, the following-tick, or mutual Partner) — all three just
  /// toggle the underlying follow edge; [currentlyFollowing] is whichever
  /// state _buildFollowButton's own StreamBuilders had in hand when this
  /// was built, so this never has to re-read anything to know which way to
  /// go.
  Future<void> _toggleFollow(bool currentlyFollowing) async {
    try {
      if (currentlyFollowing) {
        await FollowService.unfollow(widget.participant.uid);
      } else {
        await FollowService.follow(_participantAsAppUser());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  /// Host/moderator "Invite" on an audience member's own profile — the
  /// direct counterpart to a listener raising their own hand (see
  /// RoomParticipantService.setHandRaised's doc comment). Doesn't seat them
  /// itself: it just sends the invite (RoomParticipantService.
  /// sendStageInvite), which flips the button into "Waiting" (see
  /// _buildInviteButton, streamed live off the target's own doc) until they
  /// Accept — at which point VoiceRoomDetailScreen's role-watch
  /// subscription shows them the "you're invited to speak" notice, same as
  /// every other path onto the stage — or Ignore, which reverts the button
  /// back to "Invite" so the host can try again. The sheet stays open so
  /// the host actually sees that state change happen.
  Future<void> _sendStageInvite() async {
    try {
      await RoomParticipantService.sendStageInvite(
        roomId: widget.roomId,
        uid: widget.participant.uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invited ${widget.participant.name} to the stage.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not invite: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  /// The "…" menu's Mute/Unmute row — toggles the OTHER participant's mic,
  /// not the viewer's own (see RoomParticipantService.setParticipantMuted).
  Future<void> _toggleMute() async {
    final newMuted = !widget.participant.isMuted;
    try {
      await RoomParticipantService.setParticipantMuted(
        roomId: widget.roomId,
        uid: widget.participant.uid,
        muted: newMuted,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.participant.name} is now ${newMuted ? 'muted' : 'unmuted'}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update mic: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  /// The "…" menu's "Kick Out" row — fully evicts the participant from the
  /// room (RoomParticipantService.kickParticipant), not just off the stage.
  /// Confirms first: unlike moving someone back to the audience, this ends
  /// their presence in the room outright.
  Future<void> _kickOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Kick out?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          '${widget.participant.name} will be removed from this room right now.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kick Out', style: TextStyle(color: Color(0xFFE83E8C), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await RoomParticipantService.kickParticipant(roomId: widget.roomId, uid: widget.participant.uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.participant.name} was removed from the room.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  /// The "…" menu's "Report" row — same reason taxonomy as reporting a
  /// Moments post (ReportReason/ReportService), just aimed at the person
  /// directly rather than a specific post. See _showReportReasonSheet.
  Future<void> _openReport() async {
    final submitted = await _showReportReasonSheet(context);
    if (submitted == null || !mounted) return;
    try {
      await ReportService.reportUser(
        reportedUserId: widget.participant.uid,
        roomId: widget.roomId,
        reason: submitted,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your report.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit your report: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _removeFromStage() async {
    try {
      await RoomParticipantService.removeFromStage(
        roomId: widget.roomId,
        uid: widget.participant.uid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.participant.name} was moved back to the audience.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _demoteModerator() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Dismiss Moderator?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          '${widget.participant.name} will remain on stage as a speaker, but will lose moderator privileges.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Dismiss', style: TextStyle(color: Color(0xFFE83E8C), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await RoomParticipantService.demoteModeratorToSpeaker(
        roomId: widget.roomId,
        uid: widget.participant.uid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.participant.name} is no longer a moderator.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dismiss moderator: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _promoteToModerator() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Make Moderator?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'Make ${widget.participant.name} a moderator? They will be able to manage the stage and end the room.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Make Moderator', style: TextStyle(color: Color(0xFF7B68F4), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Send an invitation instead of promoting directly — the target user
      // will see the same Accept/Ignore dialog that is shown when the host
      // leaves and chooses an outgoing moderator.  The role is only written
      // if they Accept (via RoomParticipantService.promoteToModerator called
      // from VoiceRoomDetailScreen._showModeratorInviteDialog).
      await RoomParticipantService.sendModeratorInvite(
        roomId: widget.roomId,
        uid: widget.participant.uid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moderator invitation sent to ${widget.participant.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send invitation: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  String get _timeLabel {
    final hour24 = _now.hour;
    final period = hour24 >= 12 ? 'pm' : 'am';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final participant = widget.participant;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    seed: participant.uid.isNotEmpty ? participant.uid : participant.name,
                    size: 92,
                    showFlag: true,
                    flag: participant.flag,
                    imageUrl: participant.avatarUrl,
                    borderWidth: 2,
                    borderColor: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!_isSelf) ...[
                          _buildFollowButton(),
                          const SizedBox(width: 8),
                        ],
                        // Shown for host and moderator alike — this is now
                        // the only "move back to audience" control (the
                        // Host Controls card below used to have its own
                        // identically-functioning "Move to Audience" button,
                        // which just duplicated this one for the host and
                        // has been removed).
                        if (widget.canModerate && !_isSelf && widget.participant.isSeated) ...[
                          _pillButton(Icons.arrow_downward_rounded, 'Remove', onTap: _removeFromStage),
                          const SizedBox(width: 8),
                        ],
                        if (widget.canModerate && !_isSelf && !widget.participant.isSeated) ...[
                          _buildInviteButton(),
                          const SizedBox(width: 8),
                        ],
                        _buildMoreMenu(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      participant.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (participant.isHost || participant.isModerator) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: participant.isHost ? const Color(0xFFE8A23C) : const Color(0xFF7B68F4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            participant.isHost ? Icons.star_rounded : Icons.shield_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            participant.isHost ? 'Host' : 'Moderator',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _pink,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          participant.gender == 'male'
                              ? Icons.male_rounded
                              : Icons.female_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${participant.age}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _langBadge(participant.nativeLang, _green),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  _langBadge(participant.learningLang, const Color(0xFF7B68F4)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (participant.location.isNotEmpty)
                    Expanded(
                      child: Text(
                        participant.location,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Visit profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: _green,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _timeLabel,
                    style: const TextStyle(
                      color: _green,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // "Move to Audience" used to live here as its own button —
              // removed in favor of the header's "Remove" pill above (now
              // shown for the host too), which does the exact same
              // RoomParticipantService.removeFromStage call, so this card is
              // left with just the promote/demote moderator action. A seated
              // participant who isn't the host themselves (excluded by
              // _isSelf, since there's only one host per room) is always
              // either a moderator or a speaker, so one of the two branches
              // below always has something to show.
              if (widget.isHost && !_isSelf && widget.participant.isSeated) ...[
                _infoCard(
                  title: 'Host Controls',
                  child: Row(
                    children: [
                      if (participant.isModerator)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE83E8C),
                              side: const BorderSide(color: Color(0xFFE83E8C)),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('Dismiss Moderator', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: _demoteModerator,
                          ),
                        )
                      else
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF7B68F4),
                              side: const BorderSide(color: Color(0xFF7B68F4)),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.shield_rounded, size: 16),
                            label: const Text('Make Moderator', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            onPressed: _promoteToModerator,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (participant.hobbies.isNotEmpty) ...[
                _infoCard(
                  title: 'Interest & Hobbies',
                  child: Text(
                    participant.hobbies.join(' , '),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (participant.nativeLanguageFull.isNotEmpty ||
                  participant.learningLanguagesFull.isNotEmpty)
                _infoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (participant.nativeLanguageFull.isNotEmpty)
                        Text(
                          'Native Language -: ${participant.nativeLanguageFull}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (participant.learningLanguagesFull.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Learning Language ;- ${participant.learningLanguagesFull.first}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (final lang
                            in participant.learningLanguagesFull.skip(1))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Center(
                              child: Text(
                                lang,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The header's Invite button — live off the target's own
  /// `stageInvitePending` flag, so it reflects "Waiting" for every
  /// host/moderator looking at this same profile (not just the one who
  /// sent it), and reverts back to "Invite" the moment the invitee Accepts
  /// (they're seated now — this pill stops showing entirely, since
  /// `widget.participant.isSeated` gates it — see the header Row above) or
  /// Ignores (stageInvitePending just goes back to false, same pill,
  /// tappable again).
  Widget _buildInviteButton() {
    return StreamBuilder<bool>(
      stream: RoomParticipantService.streamStageInvitePending(widget.roomId, widget.participant.uid),
      builder: (context, snapshot) {
        final waiting = snapshot.data ?? false;
        return _pillButton(
          waiting ? Icons.hourglass_top_rounded : Icons.campaign_rounded,
          waiting ? 'Waiting' : 'Invite',
          onTap: waiting ? null : _sendStageInvite,
          dimmed: waiting,
        );
      },
    );
  }

  /// The header's Follow button — three states depending on the follow
  /// relationship with this participant, live and in both directions at
  /// once (nested StreamBuilders rather than a combined stream: this
  /// project has no rxdart dependency, and two small booleans don't need
  /// one just to zip together):
  ///  - neither follows the other        -> a solid "Follow" pill
  ///  - the viewer follows them, they don't follow back -> a plain check
  ///    (mirrors HelloTalk-style "requested/following" affordances
  ///    elsewhere in this app, just a single tap here since Follow is
  ///    one-sided and instant, unlike a partner request)
  ///  - both follow each other           -> a "Partner" pill
  /// Tapping any of the three toggles the underlying follow edge — there's
  /// no separate unfollow control, matching partner_profile_screen.dart's
  /// own single Follow/Following toggle button.
  Widget _buildFollowButton() {
    return StreamBuilder<bool>(
      stream: FollowService.streamIsFollowing(widget.participant.uid),
      builder: (context, followingSnap) {
        final following = followingSnap.data ?? false;
        return StreamBuilder<bool>(
          stream: FollowService.streamIsFollowedBy(widget.participant.uid),
          builder: (context, followedBySnap) {
            final followedBy = followedBySnap.data ?? false;
            final mutual = following && followedBy;

            if (mutual) {
              return _followPill(
                icon: Icons.sync_alt_rounded,
                label: 'Partner',
                onTap: () => _toggleFollow(true),
              );
            }
            if (following) {
              return _followTickButton(onTap: () => _toggleFollow(true));
            }
            return _followPill(label: 'Follow', onTap: () => _toggleFollow(false));
          },
        );
      },
    );
  }

  Widget _followPill({IconData? icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF7B68F4),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _followTickButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(color: Color(0xFF7B68F4), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _pillButton(IconData icon, String label, {VoidCallback? onTap, bool dimmed = false}) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Opacity(
        opacity: dimmed ? 0.5 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }

  Widget _iconCircle(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.white10,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: Colors.white70),
    );
  }

  /// The "…" button's own menu — Mute/Unmute, Kick Out, Report, in the same
  /// centered-text dark action-sheet voice_room_detail_screen.dart's room
  /// "…" menu uses (see widgets/dark_action_sheet.dart). Promote/demote
  /// moderator and "move to audience" used to live in this same menu, but
  /// every one of those is also already offered directly in this sheet's
  /// body (the Host Controls card for promote/demote, and the header's own
  /// "Remove" pill for move-to-audience) — nothing is actually lost by this
  /// menu no longer duplicating them.
  ///
  /// Host/moderator only (see _canActOnTarget) — a plain participant
  /// viewing someone else's profile still sees the "…" glyph, it's just
  /// inert, same as before this menu had any actions at all.
  Widget _buildMoreMenu() {
    if (!_canActOnTarget) {
      return _iconCircle(Icons.more_horiz_rounded);
    }

    return GestureDetector(
      onTap: () => showDarkActionSheet(
        context,
        items: [
          DarkActionItem(
            label: widget.participant.isMuted ? 'Unmute' : 'Mute',
            onTap: _toggleMute,
          ),
          DarkActionItem(
            label: 'Kick Out',
            color: const Color(0xFFE83E8C),
            onTap: _kickOut,
          ),
          DarkActionItem(
            label: 'Report',
            color: const Color(0xFFE83E8C),
            onTap: _openReport,
          ),
        ],
      ),
      child: _iconCircle(Icons.more_horiz_rounded),
    );
  }

  Widget _langBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoCard({String? title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// Dark-themed reason picker for the "Report" action above — the same
/// ReportReason taxonomy report_sheet.dart uses for a Moments post, just
/// styled to fit this screen instead of that one's light Moments-feed
/// look. Returns the chosen reason, or null if dismissed without
/// submitting.
Future<ReportReason?> _showReportReasonSheet(BuildContext context) {
  return showModalBottomSheet<ReportReason>(
    context: context,
    backgroundColor: const Color(0xFF1B1B3A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _ReportReasonSheet(),
  );
}

class _ReportReasonSheet extends StatefulWidget {
  const _ReportReasonSheet();

  @override
  State<_ReportReasonSheet> createState() => _ReportReasonSheetState();
}

class _ReportReasonSheetState extends State<_ReportReasonSheet> {
  ReportReason? _reason;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Report this person',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              "Help us understand what's wrong.",
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            ...ReportReason.values.map(
              (reason) => RadioListTile<ReportReason>(
                value: reason,
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                title: Text(reason.label, style: const TextStyle(color: Colors.white, fontSize: 14)),
                activeColor: const Color(0xFF7B68F4),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _reason == null ? null : () => Navigator.of(context).pop(_reason),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B68F4),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
