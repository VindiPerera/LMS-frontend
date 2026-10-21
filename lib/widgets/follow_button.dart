import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/follow_service.dart';
import '../theme/app_colors.dart';

/// A compact Follow/Following pill — the follow procedure's standard button,
/// shared by every list that shows other users (follow_list_screen.dart,
/// add_contact_screen.dart's search results). Tapping it acts immediately
/// (no navigation, no confirmation) — the live [FollowService.streamIsFollowing]
/// is what actually drives the label, so this stays correct even if the
/// same relationship changes from another screen.
class FollowButton extends StatelessWidget {
  final AppUser user;
  const FollowButton({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: FollowService.streamIsFollowing(user.id),
      initialData: false,
      builder: (context, snapshot) {
        final isFollowing = snapshot.data ?? false;
        return SizedBox(
          height: 32,
          child: OutlinedButton(
            onPressed: () {
              if (isFollowing) {
                FollowService.unfollow(user.id);
              } else {
                FollowService.follow(user);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: isFollowing
                  ? AppColors.textSecondary
                  : AppColors.primaryPurple,
              side: BorderSide(
                color: isFollowing ? AppColors.divider : AppColors.primaryPurple,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: Text(
              isFollowing ? 'Following' : 'Follow',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}
