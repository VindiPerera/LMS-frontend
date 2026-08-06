import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/room_participant.dart';
import '../../models/voiceroom.dart';
import '../../widgets/app_avatar.dart';
import 'room_profile_sheet.dart';

class VoiceRoomDetailScreen extends StatefulWidget {
  final VoiceRoom room;
  const VoiceRoomDetailScreen({super.key, required this.room});

  @override
  State<VoiceRoomDetailScreen> createState() => _VoiceRoomDetailScreenState();
}

class _VoiceRoomDetailScreenState extends State<VoiceRoomDetailScreen> {
  final _controller = TextEditingController();
  bool _subtitlesOn = false;

  static const bg = Color(0xFF1B1B3A);
  static const bubble = Color(0xFF272753);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
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
                      itemCount: boardSpeakers.length,
                      itemBuilder: (context, i) {
                        final speaker = boardSpeakers[i];
                        return GestureDetector(
                          onTap: speaker.isEmptySeat
                              ? null
                              : () => showRoomProfileSheet(context, speaker),
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
                                          seed: '${speaker.name}$i',
                                          size: 56,
                                          showFlag: true,
                                          flag: speaker.flag,
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var i = 0; i < boardStripCount; i++)
                              AppAvatar(seed: 'strip$i', size: 32),
                            AppAvatar(seed: 'me', size: 32),
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
                                '+$boardOthersCount',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
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
                          child: Column(
                            children: boardComments
                                .take(1)
                                .map((c) => _CommentLine(comment: c))
                                .toList(),
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
            _Composer(controller: _controller),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
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
  const _Composer({required this.controller});

  @override
  Widget build(BuildContext context) {
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
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF4FA8FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic_off_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF7B68F4),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.front_hand_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
