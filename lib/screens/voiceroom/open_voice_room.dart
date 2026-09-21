import 'package:flutter/material.dart';

import '../../models/voiceroom.dart';
import '../../services/room_participant_service.dart';
import 'voice_room_detail_screen.dart';

/// The single entry point every "open this room" tap in the app should go
/// through, rather than pushing VoiceRoomDetailScreen directly — checks the
/// signed-in user's kickParticipant ban status for [room] FIRST, so a
/// still-banned user never sees the room open at all.
///
/// Before this existed, the ban check only happened inside
/// VoiceRoomDetailScreen's own initState (RoomParticipantService.join),
/// after the screen had already been pushed and rendered — so the room
/// would visibly open, then pop itself back out once the async join()
/// rejection came back. Checking here instead means the room is never
/// opened for a banned user in the first place; a clear dialog explains
/// the restriction and the remaining time without ever navigating away
/// from wherever the tap happened.
///
/// The room screen still ALSO checks on its own join() as a fallback for
/// any race (a ban landing between this check and the join write actually
/// committing) — but the real, unbypassable enforcement either way is
/// firestore.rules' isBanned() on the participants/{uid} create rule; this
/// function and join()'s own check are both purely about not making a
/// banned user sit through a confusing flash of the room before finding
/// out they can't be in it.
Future<void> openVoiceRoom(
  BuildContext context,
  VoiceRoom room, {
  bool justCreated = false,
}) async {
  // A room with no real Firestore id (one of mock_data.dart's decorative
  // entries) was never joinable to begin with — nothing to check.
  if (room.id.isNotEmpty) {
    final remaining = await RoomParticipantService.banRemaining(room.id);
    if (remaining != null) {
      if (!context.mounted) return;
      await _showBannedDialog(context, remaining);
      return;
    }
  }

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VoiceRoomDetailScreen(room: room, justCreated: justCreated),
    ),
  );
}

Future<void> _showBannedDialog(BuildContext context, Duration remaining) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1B1B3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.block_rounded, color: Color(0xFFE83E8C), size: 30),
      title: const Text(
        "You can't join this room",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
      ),
      content: Text(
        'Try again after ${formatBanRemaining(remaining)}.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7B68F4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ),
  );
}
