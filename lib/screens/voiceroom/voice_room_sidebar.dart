import 'package:flutter/material.dart';

import '../../models/voiceroom.dart';
import '../../services/partner_service.dart';
import '../../services/voice_room_service.dart';
import '../../widgets/app_avatar.dart';

/// The right-hand sidebar a non-host opens from a voice room's "…" button:
/// Share / Minimize / Close icon buttons on top, with the other live rooms
/// listed below ("Recommended") so the user can hop straight into one.
///
/// Every action closes the sidebar first, then runs its callback — the
/// caller (VoiceRoomDetailScreen) keeps owning what each action actually
/// does, so the existing share sheet, minimize handoff and leave flow are
/// reused unchanged.
Future<void> showVoiceRoomSidebar(
  BuildContext context, {
  required String currentRoomId,
  required bool canShare,
  required VoidCallback onShare,
  required VoidCallback onMinimize,
  required VoidCallback onClose,
  required ValueChanged<VoiceRoom> onOpenRoom,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: _VoiceRoomSidebar(
        currentRoomId: currentRoomId,
        canShare: canShare,
        onShare: onShare,
        onMinimize: onMinimize,
        onClose: onClose,
        onOpenRoom: onOpenRoom,
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _VoiceRoomSidebar extends StatelessWidget {
  final String currentRoomId;
  final bool canShare;
  final VoidCallback onShare;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final ValueChanged<VoiceRoom> onOpenRoom;

  const _VoiceRoomSidebar({
    required this.currentRoomId,
    required this.canShare,
    required this.onShare,
    required this.onMinimize,
    required this.onClose,
    required this.onOpenRoom,
  });

  static const _panelColor = Color(0xFF1C1C1E);
  static const _buttonColor = Color(0xFF2C2C2E);

  void _run(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.82;
    return Material(
      color: _panelColor,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _IconButtonTile(
                      icon: Icons.ios_share_rounded,
                      tooltip: 'Share',
                      color: _buttonColor,
                      enabled: canShare,
                      onTap: () => _run(context, onShare),
                    ),
                    const SizedBox(width: 12),
                    _IconButtonTile(
                      icon: Icons.picture_in_picture_alt_rounded,
                      tooltip: 'Minimize',
                      color: _buttonColor,
                      onTap: () => _run(context, onMinimize),
                    ),
                    const SizedBox(width: 12),
                    _IconButtonTile(
                      icon: Icons.power_settings_new_rounded,
                      tooltip: 'Close',
                      color: _buttonColor,
                      onTap: () => _run(context, onClose),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 28, 16, 8),
                child: Text(
                  'Recommended',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<VoiceRoom>>(
                  stream: VoiceRoomService.streamActiveRooms(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                        ),
                      );
                    }
                    final rooms = snapshot.data!
                        .where((r) => r.id.isNotEmpty && r.id != currentRoomId && r.hasParticipants)
                        .toList();
                    if (rooms.isEmpty) {
                      return const Center(
                        child: Text(
                          'No other rooms right now',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: rooms.length,
                      itemBuilder: (context, i) => _RoomRow(
                        room: rooms[i],
                        onTap: () => _run(context, () => onOpenRoom(rooms[i])),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButtonTile extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _IconButtonTile({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: enabled ? Colors.white : Colors.white24, size: 24),
          ),
        ),
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  final VoiceRoom room;
  final VoidCallback onTap;

  const _RoomRow({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Host photo, or — when they have none — a colored circle
                  // with the first letter of the host's name (AppAvatar's
                  // own fallback), rather than an empty gray disc.
                  StreamBuilder<String?>(
                    stream: PartnerService.streamAvatarUrl(room.hostId),
                    initialData: room.hostAvatar.isNotEmpty ? room.hostAvatar : null,
                    builder: (context, snapshot) {
                      return AppAvatar(
                        seed: room.hostName.trim().isNotEmpty ? room.hostName.trim() : room.title,
                        size: 64,
                        imageUrl: snapshot.data ?? room.hostAvatar,
                        borderWidth: 2.5,
                        borderColor: const Color(0xFF7B68F4),
                      );
                    },
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: CountryFlagBadge(flag: room.hostFlag, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          room.category,
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.people_alt_rounded, color: Colors.white38, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${room.participantCount}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
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
