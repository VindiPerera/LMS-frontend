import 'package:flutter/material.dart';

import '../models/voiceroom.dart';
import '../screens/voiceroom/open_voice_room.dart';
import '../services/navigation_service.dart';
import '../services/voice_room_session_controller.dart';
import '../theme/app_colors.dart';
import 'app_avatar.dart';

/// Global floating "chat head" for a minimized voice room — mounted once at
/// the app root (see main.dart's MaterialApp.builder) so it survives
/// navigation across every tab and pushed screen. Reads its visibility and
/// content entirely from VoiceRoomSessionController.instance; renders
/// nothing when no room is minimized.
class VoiceRoomMiniWindow extends StatefulWidget {
  const VoiceRoomMiniWindow({super.key});

  @override
  State<VoiceRoomMiniWindow> createState() => _VoiceRoomMiniWindowState();
}

class _VoiceRoomMiniWindowState extends State<VoiceRoomMiniWindow> {
  // The card now sizes itself to content (see _MiniWindowCard) rather than
  // being force-fit into a hardcoded height — this is only an estimate used
  // to clamp/position it, kept a couple pixels above the card's actual
  // rendered height so it never sits closer to an edge than intended.
  static const _size = Size(76, 96);
  static const _edgeMargin = 8.0;
  // Reserves MainShell's 58px bottom tab bar (see main_shell.dart) so the
  // bubble can never drift on top of it, even on a screen that happens not
  // to show one right now.
  static const _bottomReserved = 74.0;

  Offset? _position;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    VoiceRoomSessionController.instance.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    VoiceRoomSessionController.instance.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Offset _clamp(Offset position, Size screen, EdgeInsets safe) {
    final minX = _edgeMargin;
    final maxX = screen.width - _size.width - _edgeMargin;
    final minY = safe.top + _edgeMargin;
    final maxY = screen.height - safe.bottom - _bottomReserved - _size.height;
    return Offset(
      position.dx.clamp(minX, maxX < minX ? minX : maxX),
      position.dy.clamp(minY, maxY < minY ? minY : maxY),
    );
  }

  void _reopen(VoiceRoom room) {
    // Give up presence ownership before navigating — the fresh
    // VoiceRoomDetailScreen about to be pushed takes it back over via its
    // own join()/heartbeat, same as any other "open this room" entry point.
    VoiceRoomSessionController.instance.clear(leaveRoom: false);
    final ctx = NavigationService.navigatorKey.currentContext;
    if (ctx != null) {
      // ignore: discarded_futures
      openVoiceRoom(ctx, room);
    }
  }

  void _close() {
    VoiceRoomSessionController.instance.clear(leaveRoom: true);
  }

  @override
  Widget build(BuildContext context) {
    final room = VoiceRoomSessionController.instance.minimizedRoom;
    if (room == null) return const SizedBox.shrink();

    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);

    _position ??= Offset(
      screen.width - _size.width - 16,
      screen.height - safe.bottom - _bottomReserved - _size.height - 24,
    );
    _position = _clamp(_position!, screen, safe);

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: _position!.dx,
      top: _position!.dy,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          setState(() {
            _position = _clamp(_position! + details.delta, screen, safe);
          });
        },
        onPanEnd: (_) => _onDragEnd(screen),
        onTap: () => _reopen(room),
        child: _MiniWindowCard(room: room, onClose: _close),
      ),
    );
  }

  void _onDragEnd(Size screen) {
    final centerX = _position!.dx + _size.width / 2;
    final snappedX = centerX < screen.width / 2
        ? _edgeMargin
        : screen.width - _size.width - _edgeMargin;
    setState(() {
      _dragging = false;
      _position = Offset(snappedX, _position!.dy);
    });
  }
}

class _MiniWindowCard extends StatelessWidget {
  final VoiceRoom room;
  final VoidCallback onClose;

  const _MiniWindowCard({required this.room, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _VoiceRoomMiniWindowState._size.width,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppAvatar(
                  seed: room.hostName,
                  imageUrl: room.hostAvatar,
                  size: 40,
                  borderWidth: 2,
                  borderColor: AppColors.primaryPurple,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    child: const Icon(Icons.mic_rounded, size: 9, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              room.hostName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
