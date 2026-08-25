import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/moment.dart';
import '../../models/user.dart';
import '../../models/voiceroom.dart';
import '../../services/follow_service.dart';
import '../../services/moment_service.dart';
import '../../services/partner_service.dart';
import '../../services/teacher_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/location_helper.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/moment_card.dart';
import '../../widgets/profile_map_header.dart';
import '../hellotalk/chat_detail_screen.dart';
import '../me/follow_list_screen.dart';
import '../voiceroom/voice_room_detail_screen.dart';

/// Full profile screen designed according to the modern HelloTalk profile spec:
/// - Top geographic map banner with city, country, and dynamic local time.
/// - Profile avatar with flag badge and interactive thumbs-up like counter.
/// - Name with gender/age badge, active status dot, and copyable handle.
/// - Language exchange row with native/learning badges and exchange indicator.
/// - Social stats (Following, Followers, Joined days).
/// - Created VoiceRoom card with "Go Look" navigation if user has created a room.
/// - Self-introduction / Bio.
/// - "About Me", "Moments", and "Achievements" segmented tabs.
/// - Bottom action bar with Follow, Chat, and Booking/Gift buttons.
class PartnerProfileScreen extends StatefulWidget {
  final AppUser initial;

  const PartnerProfileScreen({super.key, required this.initial});

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  late AppUser _user;
  int _likesCount = 1;
  bool _isLiked = false;
  bool _isFollowing = false;
  StreamSubscription<bool>? _followSub;
  int _selectedTab = 0; // 0: About Me, 1: Moments, 2: Achievements

  @override
  void initState() {
    super.initState();
    _user = widget.initial;
    _refresh();
    _followSub = FollowService.streamIsFollowing(_user.id).listen((following) {
      if (mounted) setState(() => _isFollowing = following);
    });
  }

  @override
  void dispose() {
    _followSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_user.id.isEmpty) return;
    try {
      final fresh = await PartnerService.fetchPartner(_user.id);
      if (mounted) setState(() => _user = fresh);
    } catch (_) {}
  }

  void _toggleLike() {
    HapticFeedback.lightImpact();
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
  }

  Future<void> _toggleFollow() async {
    HapticFeedback.selectionClick();
    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !wasFollowing); // optimistic

    try {
      if (wasFollowing) {
        await FollowService.unfollow(_user.id);
      } else {
        await FollowService.follow(_user);
      }
    } catch (e) {
      if (mounted) setState(() => _isFollowing = wasFollowing); // revert
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update follow status. Try again.')),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFollowing ? 'Following ${_user.name}' : 'Unfollowed ${_user.name}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _copyHandle() {
    final handleText = '@${_user.handle.isNotEmpty ? _user.handle : 'at_${_user.name.toLowerCase().replaceAll(' ', '')}'}';
    Clipboard.setData(ClipboardData(text: handleText));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $handleText to clipboard!'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final location = LocationHelper.getLocationInfo(user);
    final handleDisplay = user.handle.isNotEmpty
        ? '@${user.handle}'
        : '@at_${user.name.toLowerCase().replaceAll(' ', '')}';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Scrollable Content
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Geographic Map Banner with Location & Time Pill
                ProfileMapHeader(
                  location: location,
                  onBack: () => Navigator.of(context).maybePop(),
                  onMore: _showMoreOptions,
                ),

                // 2. Avatar & Thumbs-Up Like Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Avatar overlapping map border with Country Flag Badge
                      Transform.translate(
                        offset: const Offset(0, -32),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: AppAvatar.forUser(
                                user,
                                size: 84,
                                showFlag: false,
                                showOnlineDot: false,
                              ),
                            ),
                            // Flag badge at bottom-left of avatar
                            Positioned(
                              bottom: 2,
                              left: 2,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    user.countryFlag.isNotEmpty ? user.countryFlag : location.flag,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Thumbs-up / Like Button
                      Transform.translate(
                        offset: const Offset(0, -12),
                        child: GestureDetector(
                          onTap: _toggleLike,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: _isLiked ? const Color(0xFFFFE8E8) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                                  size: 16,
                                  color: _isLiked ? const Color(0xFFE53935) : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$_likesCount',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _isLiked ? const Color(0xFFE53935) : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Name, Gender/Age Badge, and Active Status
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Gender / Age Pill
                            _buildGenderAgeBadge(user),
                            const Spacer(),
                            // Active status dot & label
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.online,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  user.activeLabel.isNotEmpty ? user.activeLabel : 'Active now',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 5),

                        // Handle with copy icon
                        GestureDetector(
                          onTap: _copyHandle,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                handleDisplay,
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 4. Language Exchange Row (Native ⇆ Learning)
                        _buildLanguageExchangeRow(user),

                        const SizedBox(height: 14),

                        // 5. Social Counts Row (Following, Followers, Joined days)
                        _buildSocialStatsRow(user),

                        const SizedBox(height: 16),

                        // 6. Created VoiceRoom Card (Firestore live stream)
                        StreamBuilder<VoiceRoom?>(
                          stream: VoiceRoomService.streamActiveRoomForUser(
                            user.id.isNotEmpty ? user.id : '',
                          ),
                          builder: (context, snap) {
                            final room = snap.data;
                            if (room == null) return const SizedBox.shrink();
                            return Column(
                              children: [
                                _buildVoiceRoomCard(room),
                                const SizedBox(height: 16),
                              ],
                            );
                          },
                        ),

                        // 7. Self-introduction / Bio
                        Text(
                          user.bio.isNotEmpty
                              ? user.bio
                              : "${user.name} hasn't filled out their self-introduction",
                          style: TextStyle(
                            fontSize: 14.5,
                            color: user.bio.isNotEmpty ? AppColors.textPrimary : AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // 8. Navigation Segmented Tabs (About Me, Moments, Achievements)
                        _buildSegmentedTabs(),

                        const SizedBox(height: 16),

                        // 9. Tab Content
                        _buildTabContent(user, location),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 10. Bottom Action Bar (Follow, Chat, and Book/Gift Button)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomActionBar(user),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderAgeBadge(AppUser user) {
    final isMale = user.gender.toLowerCase() == 'male';
    final age = user.age > 0 ? user.age : 26;
    final bgColor = isMale ? const Color(0xFFE8F2FF) : const Color(0xFFFFEEF5);
    final textColor = isMale ? const Color(0xFF1E88E5) : const Color(0xFFE91E63);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMale ? Icons.male_rounded : Icons.female_rounded,
            size: 13,
            color: textColor,
          ),
          const SizedBox(width: 1),
          Text(
            '$age',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageExchangeRow(AppUser user) {
    final nativeCode = user.nativeLang.languageCode;
    final learningCode = user.learningLang.languageCode;

    return Row(
      children: [
        // Native Language Badge
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nativeCode,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              height: 2.5,
              width: 22,
              margin: const EdgeInsets.only(top: 2, bottom: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00C48C),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              user.nativeLang.isNotEmpty ? user.nativeLang : 'Sinhala',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        const SizedBox(width: 18),

        // Exchange Icon
        const Icon(
          Icons.swap_horiz_rounded,
          size: 20,
          color: AppColors.textTertiary,
        ),

        const SizedBox(width: 18),

        // Learning Language Badge
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              learningCode,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              height: 2.5,
              width: 22,
              margin: const EdgeInsets.only(top: 2, bottom: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              user.learningLang.isNotEmpty ? user.learningLang : 'English',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialStatsRow(AppUser user) {
    return Row(
      children: [
        StreamBuilder<int>(
          stream: FollowService.streamFollowingCount(user.id),
          initialData: 0,
          builder: (context, snapshot) => _statItem(
            '${snapshot.data ?? 0}',
            'Following',
            onTap: () => _openFollowList(context, user, 0),
          ),
        ),
        const SizedBox(width: 18),
        StreamBuilder<int>(
          stream: FollowService.streamFollowersCount(user.id),
          initialData: 0,
          builder: (context, snapshot) => _statItem(
            '${snapshot.data ?? 0}',
            'Followers',
            onTap: () => _openFollowList(context, user, 1),
          ),
        ),
        const SizedBox(width: 18),
        _statItem('10d', 'Joined'),
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

  Widget _statItem(String number, String label, {VoidCallback? onTap}) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          number,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: content);
  }

  Widget _buildVoiceRoomCard(VoiceRoom room) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          // Voice room avatar with flag and microphone badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8DEF8),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    room.hostAvatar.isNotEmpty ? room.hostAvatar : '🎙',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                left: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      room.hostFlag.isNotEmpty ? room.hostFlag : '🇨🇦',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryPurple,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 12),

          // Room details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    room.tag.isNotEmpty ? room.tag : 'EN',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'ııı ',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        room.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // "Go Look" Action Button
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoiceRoomDetailScreen(room: room),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6B47EB),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Go Look',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedTabs() {
    return Row(
      children: [
        _pillTab(0, 'About Me'),
        const SizedBox(width: 10),
        _pillTab(1, 'Moments 0'),
        const SizedBox(width: 10),
        _pillTab(2, 'Achievements'),
      ],
    );
  }

  Widget _pillTab(int index, String title) {
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3F4F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppUser user, LocationInfo location) {
    if (_selectedTab == 1) {
      // Moments tab
      return StreamBuilder<List<Moment>>(
        stream: user.id.isNotEmpty
            ? MomentService.streamUserMoments(userId: user.id)
            : const Stream.empty(),
        builder: (context, snapshot) {
          final moments = snapshot.data ?? const [];
          if (moments.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No moments shared yet.',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: moments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => MomentCard(moment: moments[i]),
          );
        },
      );

    }

    if (_selectedTab == 2) {
      // Achievements tab
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _achievementTile(Icons.emoji_events_rounded, 'First Conversation', 'Completed first language exchange', true),
            const Divider(height: 16),
            _achievementTile(Icons.local_fire_department_rounded, '7-Day Streak', 'Practiced daily language learning', true),
            const Divider(height: 16),
            _achievementTile(Icons.school_rounded, 'Fluent Explorer', 'Joined 10+ voice study rooms', true),
          ],
        ),
      );
    }

    // Default "About Me" tab
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                '10d Joined',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(width: 24),
              const Icon(Icons.menu_book_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                '1 Point',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Country & Real Time details
          Row(
            children: [
              const Icon(Icons.public_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Country: ${location.country}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 20),
              const Icon(Icons.access_time_rounded, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Time: ${location.timeLabel}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),

          if (user.tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: user.tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
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

  Widget _buildBottomActionBar(AppUser user) {
    final isTeacher = user.role == 'teacher';

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Follow Button
          Expanded(
            flex: 4,
            child: OutlinedButton(
              onPressed: _toggleFollow,
              style: OutlinedButton.styleFrom(
                backgroundColor: _isFollowing ? const Color(0xFFF3F4F6) : const Color(0xFFF5F2FF),
                side: BorderSide(
                  color: _isFollowing ? Colors.transparent : const Color(0xFF6B47EB).withValues(alpha: 0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(
                _isFollowing ? 'Following' : 'Follow',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _isFollowing ? AppColors.textSecondary : const Color(0xFF6B47EB),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Chat Button
          Expanded(
            flex: 5,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(user: user),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B47EB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'Chat',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Booking / Calendar / Gift Button (Pink circle)
          GestureDetector(
            onTap: () {
              if (isTeacher) {
                TeacherService.bookTutor(context, teacher: user);
              } else {
                _showBookOrGiftSheet(user);
              }
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: Color(0xFFE91E63),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBookOrGiftSheet(AppUser user) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Practice & Connect',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.school_rounded, color: Color(0xFF6B47EB)),
                title: const Text('Book 1-on-1 Session'),
                subtitle: const Text('Schedule conversation practice'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  TeacherService.bookTutor(context, teacher: user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_rounded, color: AppColors.online),
                title: const Text('Send Quick Greeting 👋'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ChatDetailScreen(user: user)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Share Profile'),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile link copied!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: AppColors.badgeRed),
              title: const Text('Block User', style: TextStyle(color: AppColors.badgeRed)),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Blocked ${_user.name}')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
