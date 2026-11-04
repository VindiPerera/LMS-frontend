import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../theme/app_colors.dart';
import '../../widgets/achievements_card.dart';

/// me_screen.dart's "Achievements" settings entry — the signed-in user's
/// own view of the same real, computed milestones partner_profile_screen.dart
/// shows for anyone else's profile (see AchievementsCard).
class MyAchievementsScreen extends StatelessWidget {
  final AppUser user;

  const MyAchievementsScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Achievements', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [AchievementsCard(user: user)],
        ),
      ),
    );
  }
}
