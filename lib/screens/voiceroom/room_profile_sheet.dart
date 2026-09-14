import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/room_participant.dart';
import '../../services/friend_service.dart';
import '../../services/room_participant_service.dart';
import '../../widgets/app_avatar.dart';

Future<void> showRoomProfileSheet(
  BuildContext context,
  RoomParticipant participant, {
  required String roomId,
  required bool canModerate,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => RoomProfileSheet(
      participant: participant,
      roomId: roomId,
      canModerate: canModerate,
    ),
  );
}

class RoomProfileSheet extends StatefulWidget {
  final RoomParticipant participant;
  final String roomId;
  final bool canModerate;
  const RoomProfileSheet({
    super.key,
    required this.participant,
    required this.roomId,
    required this.canModerate,
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

  Future<void> _sendPartnerRequest() async {
    try {
      await FriendService.instance.sendFriendRequest(widget.participant.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Partner request sent to ${widget.participant.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: ${e.toString().replaceFirst('Exception: ', '')}')),
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
                    seed: participant.name,
                    size: 92,
                    showFlag: true,
                    flag: participant.flag,
                    borderWidth: 2,
                    borderColor: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!_isSelf) ...[
                          StreamBuilder<FriendStatus>(
                            stream: FriendService.instance.streamFriendshipStatus(widget.participant.uid),
                            builder: (context, snapshot) {
                              final status = snapshot.data ?? FriendStatus.none;
                              final canSend = status == FriendStatus.none;
                              final label = switch (status) {
                                FriendStatus.friends => 'Partners',
                                FriendStatus.pending => 'Requested',
                                FriendStatus.incoming => 'Respond',
                                _ => 'Partner',
                              };
                              return _pillButton(
                                Icons.sync_alt_rounded,
                                label,
                                onTap: canSend ? _sendPartnerRequest : null,
                                dimmed: !canSend,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.canModerate && !_isSelf && widget.participant.isSeated) ...[
                          _pillButton(Icons.mic_off_rounded, 'Remove', onTap: _removeFromStage),
                          const SizedBox(width: 8),
                        ],
                        _iconCircle(Icons.more_horiz_rounded),
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
