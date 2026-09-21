import 'package:flutter/material.dart';

import '../models/voiceroom.dart';
import '../screens/voiceroom/open_voice_room.dart';
import '../services/voice_room_service.dart';

/// A tappable "join this Voice Room" card — what a shared room looks like
/// wherever it's been shared to: a chat bubble (chat_detail_screen.dart,
/// for a message with `type == MessageType.voiceRoomInvite`) or a Moments
/// post (moment_card.dart, for a moment with `hasVoiceRoomCard`). Same
/// gradient/"LIVE NOW" styling as chat_detail_screen.dart's
/// `_PartnerVoiceRoomBanner` ("this person is hosting right now"), reused
/// here so a shared room reads the same way everywhere it shows up.
///
/// [title]/[hostName]/[hostAvatar] are the snapshot taken at share time
/// (denormalized onto the message/moment so the card still shows something
/// if the room is later renamed or removed); the live `voiceRooms/{roomId}`
/// doc is streamed on top so the LIVE/Ended state and listener count stay
/// current without needing the card to be rebuilt from outside.
class VoiceRoomInviteCard extends StatelessWidget {
  final String roomId;
  final String title;
  final String hostName;
  final String hostAvatar;

  const VoiceRoomInviteCard({
    super.key,
    required this.roomId,
    required this.title,
    required this.hostName,
    required this.hostAvatar,
  });

  Future<void> _join(BuildContext context) async {
    // Re-fetched fresh rather than reusing the streamed snapshot below: this
    // also doubles as the permission check (fetchRoom treats a
    // permission-denied read — the room's audience no longer including this
    // viewer — the same as "doesn't exist", see VoiceRoomService.fetchRoom),
    // exactly the "still active and they have permission to join" gate this
    // card needs before handing off to VoiceRoomDetailScreen.
    final room = await VoiceRoomService.fetchRoom(roomId);
    if (!context.mounted) return;
    if (room == null || !room.isActive) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This Voice Room has ended.')),
        );
      return;
    }
    await openVoiceRoom(context, room);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VoiceRoom?>(
      stream: VoiceRoomService.streamRoom(roomId),
      builder: (context, snapshot) {
        // Optimistic default while the live doc is still loading: assume
        // still active rather than flashing "Ended" for a moment on every
        // render — matches how _PartnerVoiceRoomBanner elsewhere in the app
        // only ever renders once a room is confirmed live.
        final live = snapshot.data;
        final isActive = live?.isActive ?? true;
        final displayTitle = (live?.title.isNotEmpty ?? false) ? live!.title : title;
        final displayHost = (live?.hostName.isNotEmpty ?? false) ? live!.hostName : hostName;
        final displayAvatar = (live?.hostAvatar.isNotEmpty ?? false) ? live!.hostAvatar : hostAvatar;
        final listenerCount = live?.participantCount;

        return Container(
          margin: const EdgeInsets.only(top: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isActive ? () => _join(context) : null,
            child: Opacity(
              opacity: isActive ? 1 : 0.6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8E2DE2).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white24,
                      backgroundImage: displayAvatar.isNotEmpty ? NetworkImage(displayAvatar) : null,
                      child: displayAvatar.isEmpty
                          ? const Icon(Icons.mic_rounded, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.redAccent : Colors.white24,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isActive ? 'LIVE NOW' : 'ENDED',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '$displayHost is hosting',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayTitle.isEmpty ? 'Voice Room' : displayTitle,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isActive && listenerCount != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '$listenerCount listening',
                              style: const TextStyle(color: Colors.white60, fontSize: 10.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Join',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8E2DE2)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
