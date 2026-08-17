import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/live_stream.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

class LiveTab extends StatelessWidget {
  const LiveTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: mockLiveStreams.length,
      itemBuilder: (context, i) => _LiveCard(stream: mockLiveStreams[i]),
    );
  }
}

class _LiveCard extends StatelessWidget {
  final LiveStream stream;
  const _LiveCard({required this.stream});

  static const _gradients = {
    'live_a': [Color(0xFF7A1E4E), Color(0xFF3A0D28)],
    'live_b': [Color(0xFF241F5E), Color(0xFF120F30)],
    'live_c': [Color(0xFF6B1E4A), Color(0xFF2A0C1E)],
    'live_d': [Color(0xFF241F5E), Color(0xFF120F30)],
    'live_e': [Color(0xFF7A1E4E), Color(0xFF3A0D28)],
    'live_f': [Color(0xFF6B1E4A), Color(0xFF2A0C1E)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[stream.coverSeed] ?? _gradients['live_a']!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pill('EN', Colors.white24, Colors.white),
              const SizedBox(width: 5),
              Flexible(
                child: _pill(
                  '# ${stream.tag}',
                  AppColors.primaryPurple.withValues(alpha: 0.3),
                  AppColors.primaryPurple.withValues(alpha: 0.95),
                  ellipsis: true,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: AppAvatar(
              seed: stream.hostName,
              size: 56,
              showFlag: true,
              flag: stream.hostFlag,
            ),
          ),
          const Spacer(),
          Text(
            stream.hostName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stream.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.remove_red_eye_outlined,
                size: 13,
                color: Colors.white60,
              ),
              const SizedBox(width: 4),
              Text(
                '${stream.viewers}',
                style: const TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
              const Spacer(),
              if (stream.badgeLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: stream.badgeLabel == 'Hot'
                        ? AppColors.vipGold
                        : AppColors.badgePink,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stream.badgeLabel == 'Hot' ? '🔥 Hot' : '★ Creator',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg, {bool ellipsis = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
        style: TextStyle(fontSize: 9.5, color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
