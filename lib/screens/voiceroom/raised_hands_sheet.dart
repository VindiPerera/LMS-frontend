import 'package:flutter/material.dart';

import '../../models/room_participant.dart';
import '../../services/room_participant_service.dart';
import '../../widgets/app_avatar.dart';

const Color _bubble = Color(0xFF272753);
const Color _accent = Color(0xFF7B68F4);

/// A hand icon with a live count of everyone currently waiting with a
/// raised hand — a rounded-square "app icon" look (not a plain circle) with
/// a small red counter badge overlapping its corner, matching this app's
/// other notification-style icons. Sits in the live comment feed's own
/// corner (see voice_room_detail_screen.dart), always visible there for the
/// host/moderator so incoming requests are never missed.
class RaisedHandsBadge extends StatelessWidget {
  final Stream<List<RoomParticipant>> stream;
  final VoidCallback onTap;
  const RaisedHandsBadge({super.key, required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomParticipant>>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF4A4A6E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Icon(Icons.front_hand_rounded, color: Colors.white, size: 17),
                ),
                if (count > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFF1B1B3A), width: 1.5),
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
                      ),
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

/// Host/moderator's review queue — everyone currently waiting with a raised
/// hand, oldest request first. Each row can be accepted (seats them,
/// clearing the flag) or declined (clears the flag without seating them) on
/// its own; a row also toggles into a multi-select so several people can be
/// added to the stage in one "Add N to Stage" tap, stopping cleanly (and
/// saying so) the moment seats run out partway through.
Future<void> showRaisedHandsSheet(BuildContext context, {required String roomId}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: _bubble,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RaisedHandsSheet(roomId: roomId),
  );
}

class _RaisedHandsSheet extends StatefulWidget {
  final String roomId;
  const _RaisedHandsSheet({required this.roomId});

  @override
  State<_RaisedHandsSheet> createState() => _RaisedHandsSheetState();
}

class _RaisedHandsSheetState extends State<_RaisedHandsSheet> {
  final Set<String> _selected = {};
  bool _processing = false;

  Future<void> _acceptOne(RoomParticipant p) async {
    try {
      await RoomParticipantService.acceptRaisedHand(roomId: widget.roomId, uid: p.uid);
      if (mounted) setState(() => _selected.remove(p.uid));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _declineOne(RoomParticipant p) async {
    try {
      await RoomParticipantService.declineRaisedHand(roomId: widget.roomId, uid: p.uid);
      if (mounted) setState(() => _selected.remove(p.uid));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not dismiss: ${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  /// Accepts everyone currently selected, one at a time — stops the moment
  /// one fails (seats ran out) rather than firing the rest, since every
  /// later attempt would just fail the exact same way; reports how many
  /// actually made it up either way.
  Future<void> _acceptSelected(List<RoomParticipant> people) async {
    final targets = people.where((p) => _selected.contains(p.uid)).toList();
    if (targets.isEmpty || _processing) return;
    setState(() => _processing = true);

    var accepted = 0;
    String? failure;
    for (final p in targets) {
      try {
        await RoomParticipantService.acceptRaisedHand(roomId: widget.roomId, uid: p.uid);
        accepted++;
      } catch (e) {
        failure = e.toString().replaceFirst('Exception: ', '');
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _selected.clear();
      _processing = false;
    });
    final message = failure == null
        ? 'Added $accepted to the stage.'
        : accepted > 0
            ? 'Added $accepted to the stage. $failure'
            : failure;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleSelected(String uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: StreamBuilder<List<RoomParticipant>>(
          stream: RoomParticipantService.streamRaisedHands(widget.roomId),
          builder: (context, snapshot) {
            final people = snapshot.data ?? const <RoomParticipant>[];
            // Only counts people still actually in the live queue — a
            // selection can't silently overcount someone who left, got
            // kicked, or was already handled from another device while
            // this sheet was open.
            final selectedCount = people.where((p) => _selected.contains(p.uid)).length;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Raised hands',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: people.isEmpty
                      ? const Center(
                          child: Text(
                            'No one has raised their hand yet.',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: people.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white12),
                          itemBuilder: (context, i) {
                            final p = people[i];
                            final selected = _selected.contains(p.uid);
                            return ListTile(
                              onTap: () => _toggleSelected(p.uid),
                              leading: AppAvatar(
                                seed: p.uid.isNotEmpty ? p.uid : p.name,
                                size: 44,
                                showFlag: true,
                                flag: p.flag,
                                imageUrl: p.avatarUrl,
                              ),
                              title: Text(
                                p.name,
                                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    _langBadge(p.nativeLang, const Color(0xFF3DDC97)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.sync_alt_rounded, size: 12, color: Colors.white38),
                                    const SizedBox(width: 6),
                                    _langBadge(p.learningLang, _accent),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                    color: selected ? _accent : Colors.white24,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: () => _declineOne(p),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 17),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _acceptOne(p),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (selectedCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _processing ? null : () => _acceptSelected(people),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: _processing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Add $selectedCount to Stage', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _langBadge(String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: color, width: 1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
