import 'package:flutter/material.dart';
import '../../data/mock_data.dart' as mock;
import '../../models/moment.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../services/moment_service.dart';
import '../../services/payment_api_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/payment_method_sheet.dart';
import '../auth/splash_screen.dart';
import '../friends/my_qr_code_screen.dart';
import '../moments/user_moments_screen.dart';
import '../voiceroom/voice_room_detail_screen.dart';
import 'course_detail_sheet.dart';
import 'edit_profile_screen.dart';
import 'follow_list_screen.dart';
import 'vip_calendar_screen.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  // Falls back to the old mock profile only if we somehow reach this screen
  // without a logged-in user (shouldn't happen — MainShell is only reachable
  // post-login — but keeps the tab from crashing rather than showing it).
  AppUser get _user => AuthService.instance.currentUser ?? mock.currentUser;

  @override
  void initState() {
    super.initState();
    // Pulls the latest profile from the backend (e.g. edited on another
    // device) rather than only showing what was cached at login.
    AuthService.instance.refreshCurrentUser().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<AppUser>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(user: _user)),
    );
    if (updated != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          children: [
            _VipPromoBanner(),
            const SizedBox(height: 18),
            _ProfileHeader(user: user, onEdit: _editProfile),
            if (user.tags.isNotEmpty) ...[
              const SizedBox(height: 14),
              _InterestsSection(tags: user.tags),
            ],
            const SizedBox(height: 18),
            _MyVoiceRoomBanner(),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: '🔥',
                    value: '1',
                    label: 'Day Streak',
                    trailing: '🎁',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(icon: null, value: '0', label: 'Visitors'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MomentsRow(user: user),
            if (user.isVip) ...[
              const SizedBox(height: 12),
              _VipCalendarRow(user: user),
            ],
            // const SizedBox(height: 18),
            // _VipBenefitsCard(),
            const SizedBox(height: 22),
            const Text(
              'Language Courses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _CoursesGrid(),
            const SizedBox(height: 20),
            _SettingsList(),
          ],
        ),
      ),
    );
  }
}

class _VipPromoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.vipBannerGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Learn more about exclusive VIP privileges',
              style: TextStyle(
                color: AppColors.vipCardText,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _VipBenefitsCard(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'View Now',
                style: TextStyle(
                  color: AppColors.vipCardText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AppUser user;
  final VoidCallback onEdit;

  const _ProfileHeader({required this.user, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 78,
              height: 78,
              child: Stack(
                children: [
                  SizedBox(
                    width: 78,
                    height: 78,
                    child: CircularProgressIndicator(
                      value: user.profileCompleted ? 1 : 0.45,
                      strokeWidth: 3,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primaryPurple,
                      ),
                    ),
                  ),
                  Center(child: AppAvatar(seed: user.name, size: 66)),
                ],
              ),
            ),
            Positioned(
              bottom: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  user.profileCompleted ? '100%' : '45%',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (user.isVip) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'VIP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.vipGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '@${user.handle}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.copy_rounded,
                    size: 12,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  StreamBuilder<int>(
                    stream: FollowService.streamFollowingCount(user.id),
                    initialData: 0,
                    builder: (context, snapshot) => _FollowStat(
                      count: snapshot.data ?? 0,
                      label: 'Following',
                      onTap: () => _openFollowList(context, user, 0),
                    ),
                  ),
                  const SizedBox(width: 14),
                  StreamBuilder<int>(
                    stream: FollowService.streamFollowersCount(user.id),
                    initialData: 0,
                    builder: (context, snapshot) => _FollowStat(
                      count: snapshot.data ?? 0,
                      label: 'Followers',
                      onTap: () => _openFollowList(context, user, 1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Edit',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openFollowList(BuildContext context, AppUser user, int initialTab) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowListScreen(
          uid: user.id,
          userName: user.name,
          initialTab: initialTab,
        ),
      ),
    );
  }
}

class _FollowStat extends StatelessWidget {
  final int count;
  final String label;
  final VoidCallback onTap;

  const _FollowStat({
    required this.count,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count ',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Chips for `AppUser.tags` (picked on select_interests_screen.dart right
/// after signup) — the signed-in user's own equivalent of the "Interest &
/// Hobbies" chips shown on partner_profile_screen.dart / friend_profile_
/// screen.dart for other people.
class _InterestsSection extends StatelessWidget {
  final List<String> tags;
  const _InterestsSection({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Interest & Hobbies',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String? icon;
  final String value;
  final String label;
  final String? trailing;
  const _StatCard({
    this.icon,
    required this.value,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (icon != null)
                    Text(icon!, style: const TextStyle(fontSize: 18)),
                  if (icon != null) const SizedBox(width: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (trailing != null)
                Text(trailing!, style: const TextStyle(fontSize: 20)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentsRow extends StatelessWidget {
  final AppUser user;
  const _MomentsRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Moment>>(
      stream: MomentService.streamUserMoments(userId: user.id),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserMomentsScreen(
                  userId: user.id.isNotEmpty ? user.id : user.handle,
                  userName: user.name,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: AppColors.primaryPurple,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'My Moments',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VipCalendarRow extends StatelessWidget {
  final AppUser user;
  const _VipCalendarRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VipCalendarScreen(user: user)),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.vipGold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: AppColors.vipGold,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'VIP membership calendar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _VipBenefitsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.vipCardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('👑', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                'VIP benefits',
                style: TextStyle(
                  color: AppColors.vipCardText,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                'Free',
                style: TextStyle(
                  color: AppColors.vipCardText.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 26),
              Text(
                'VIP',
                style: TextStyle(
                  color: AppColors.vipCardText,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _benefitRow('Unlimited Translations', '5 times/day', true),
          const SizedBox(height: 10),
          _benefitRow('Unlock Visitors page', '—', true),
          const SizedBox(height: 10),
          _benefitRow('Search nearby Users', '—', true),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _subscribe(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(
                'Subscribe — \$${VipPlan.thirtyDays.amount.toStringAsFixed(2)} / 30 days',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _subscribe(BuildContext context) async {
    // Captured before any pop below — a plain `context` variable stops
    // being safely usable for widget lookups once the sheet that owns it
    // closes, but this messenger reference stays valid.
    final messenger = ScaffoldMessenger.of(context);

    final purchased = await PaymentMethodSheet.show(context, plan: VipPlan.thirtyDays);
    if (purchased != true) return;

    await AuthService.instance.refreshCurrentUser();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close this VIP-benefits sheet too — done.
    messenger.showSnackBar(
      const SnackBar(content: Text("🎉 You're VIP for the next 30 days!")),
    );
  }

  Widget _benefitRow(String label, String freeValue, bool vipCheck) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: TextStyle(color: AppColors.vipCardText, fontSize: 13.5),
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            freeValue,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.vipCardText.withValues(alpha: 0.45),
              fontSize: 12.5,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Icon(
            Icons.check_rounded,
            color: AppColors.vipCardText,
            size: 18,
          ),
        ),
      ],
    );
  }
}

class _CoursesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
      ),
      itemCount: mock.languageCourses.length,
      itemBuilder: (context, i) {
        final course = mock.languageCourses[i];
        final name = course['name'] as String;
        // Only these 4 have a detail sheet behind them so far; the rest
        // (HelloWords/HelloEnglish/Podcast/Grammar) are untouched.
        const wired = {'Teachers', 'LiveClass', 'Idioms', 'Flashcards'};

        return GestureDetector(
          onTap: wired.contains(name)
              ? () => CourseDetailSheet.show(context, name)
              : null,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: course['color'] as Color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      course['icon'] as IconData,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  if (course['badge'] as bool)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.badgeRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                course['name'] as String,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsList extends StatelessWidget {
  static const _items = [
    ('My Progress', Icons.bar_chart_rounded),
    ('Achievements', Icons.emoji_events_outlined),
    ('Saved Words & Sentences', Icons.bookmark_border_rounded),
    ('Blocked Users', Icons.block_rounded),
    ('Invite Friends', Icons.person_add_alt_rounded),
    ('Help & Feedback', Icons.help_outline_rounded),
    ('Log Out', Icons.logout_rounded),
  ];

  Future<void> _handleTap(BuildContext context, String label) async {
    if (label == 'Invite Friends') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MyQRCodeScreen()),
      );
      return;
    }
    if (label == 'Log Out') {
      await AuthService.instance.logout();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $label...'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(_items.length, (i) {
          final (label, icon) = _items[i];
          final isLogout = label == 'Log Out';
          return Column(
            children: [
              ListTile(
                leading: Icon(
                  icon,
                  color: isLogout
                      ? AppColors.badgeRed
                      : AppColors.textSecondary,
                  size: 20,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isLogout ? AppColors.badgeRed : null,
                  ),
                ),
                trailing: isLogout
                    ? null
                    : const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textTertiary,
                      ),
                onTap: () => _handleTap(context, label),
              ),
              if (i != _items.length - 1)
                const Divider(height: 1, indent: 52, color: AppColors.divider),
            ],
          );
        }),
      ),
    );
  }
}

/// Banner that appears on the Me tab when the signed-in user is currently
/// hosting a Voice Room — shows a gradient live card with "End Room" option.
class _MyVoiceRoomBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VoiceRoom?>(
      stream: VoiceRoomService.streamMyActiveRoom(),
      builder: (context, snapshot) {
        final room = snapshot.data;
        if (room == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8E2DE2).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              // Pulsing mic icon
              const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white24,
                child: Icon(Icons.mic_rounded, color: Colors.white, size: 22),
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
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '● LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${room.participantCount} listener${room.participantCount == 1 ? '' : 's'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      room.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VoiceRoomDetailScreen(room: room),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryPurple,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Go Live', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () async {
                      await VoiceRoomService.endRoom(room.id);
                    },
                    child: const Text(
                      'End Room',
                      style: TextStyle(color: Colors.white60, fontSize: 11, decoration: TextDecoration.underline, decorationColor: Colors.white60),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
