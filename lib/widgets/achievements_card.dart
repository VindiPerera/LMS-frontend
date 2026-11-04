import 'package:flutter/material.dart';

import '../models/moment.dart';
import '../models/user.dart';
import '../services/follow_service.dart';
import '../services/moment_service.dart';
import '../theme/app_colors.dart';

/// Real, computed milestones for [user] — picked from data that's (a)
/// already tracked with no new backend work, and (b) actually readable for
/// ANY profile, not just the signed-in user's own: a viewer can only ever
/// query a group's member list if they're a member themselves (see
/// firestore.rules' chats/{chatId} read rule), so "groups joined" — the
/// other obvious candidate — can't be a general profile stat the way
/// moments/followers/join-date already are.
///
/// Shared by partner_profile_screen.dart's Achievements tab and
/// me_screen.dart's own "Achievements" settings entry (via
/// MyAchievementsScreen) — same milestones either way, since they're
/// equally meaningful (and equally readable) for any profile.
class AchievementsCard extends StatelessWidget {
  final AppUser user;

  const AchievementsCard({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final createdAt = user.createdAt;
    final daysJoined = createdAt == null ? 0 : DateTime.now().difference(createdAt).inDays;

    return StreamBuilder<List<Moment>>(
      stream: user.id.isEmpty
          ? const Stream<List<Moment>>.empty()
          : MomentService.streamUserMoments(userId: user.id),
      builder: (context, momentsSnapshot) {
        final momentsCount = momentsSnapshot.data?.length ?? 0;
        return StreamBuilder<int>(
          stream: FollowService.streamFollowersCount(user.id),
          initialData: 0,
          builder: (context, followersSnapshot) {
            final followersCount = followersSnapshot.data ?? 0;

            final achievements = <(IconData, String, String, bool)>[
              (Icons.celebration_rounded, 'Joined FaceTalk', 'Created a FaceTalk account', createdAt != null),
              (Icons.calendar_today_rounded, '1 Week Member', 'On FaceTalk for 7+ days', daysJoined >= 7),
              (Icons.calendar_month_rounded, '1 Month Member', 'On FaceTalk for 30+ days', daysJoined >= 30),
              (Icons.photo_camera_rounded, 'First Moment', 'Shared their first Moment', momentsCount >= 1),
              (Icons.edit_note_rounded, 'Content Creator', 'Shared 10+ Moments', momentsCount >= 10),
              (Icons.star_rounded, 'Rising Star', 'Reached 10+ followers', followersCount >= 10),
            ];

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < achievements.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _achievementTile(
                      achievements[i].$1,
                      achievements[i].$2,
                      achievements[i].$3,
                      achievements[i].$4,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _achievementTile(IconData icon, String title, String subtitle, bool unlocked) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: unlocked ? const Color(0xFFFFD54F).withValues(alpha: 0.2) : Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: unlocked ? const Color(0xFFF57F17) : Colors.grey, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}
