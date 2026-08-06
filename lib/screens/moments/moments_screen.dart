import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/moment.dart';
import '../../models/user.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

class MomentsScreen extends StatelessWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                SizedBox(width: 8),
                Text(
                  'FIFA World Cup',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () {},
            ),
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {}),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppColors.primaryPurple,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Recent'),
              Tab(text: 'Help'),
              Tab(text: 'Following'),
              Tab(text: 'Learn'),
              Tab(text: 'Selfie'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RecentFeed(),
            const Center(
              child: Text(
                'Help posts',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
            const Center(
              child: Text(
                'Following posts',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
            const Center(
              child: Text(
                'Learn posts',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
            const Center(
              child: Text(
                'Selfie posts',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: AppColors.primaryPurple,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }
}

class _RecentFeed extends StatelessWidget {
  const _RecentFeed();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: mockMoments.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return const _PostPromptBanner();
        return _MomentCard(moment: mockMoments[i - 1]);
      },
    );
  }
}

class _PostPromptBanner extends StatelessWidget {
  const _PostPromptBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.travel_explore_rounded,
              color: AppColors.primaryPurple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Post your first Moment',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                SizedBox(height: 2),
                Text(
                  'More partners will see you and reach out to learn together!',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              'Post',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  final Moment moment;
  const _MomentCard({required this.moment});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar.forUser(moment.user, size: 44, showFlag: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moment.user.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _langBadge(
                          moment.user.nativeLang.languageCode,
                          AppColors.perfectGreen,
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.sync_alt_rounded,
                          size: 12,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        _langBadge(
                          moment.user.learningLang.languageCode,
                          AppColors.primaryPurple,
                          dotted: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                moment.timeAgo,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (moment.tag != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '#${moment.tag}',
                style: const TextStyle(
                  color: AppColors.primaryPurple,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(moment.text, style: const TextStyle(fontSize: 14, height: 1.35)),
          if (moment.isTranslatable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: const [
                  Icon(
                    Icons.translate_rounded,
                    size: 14,
                    color: AppColors.primaryPurple,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Translate',
                    style: TextStyle(
                      color: AppColors.primaryPurple,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (moment.imageUrl != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6FA8DC), Color(0xFF3D8B5F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_rounded,
                color: Colors.white54,
                size: 40,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _actionIcon(Icons.favorite_border_rounded, '${moment.likes}'),
              const SizedBox(width: 20),
              _actionIcon(
                Icons.chat_bubble_outline_rounded,
                '${moment.comments}',
              ),
              const Spacer(),
              const Icon(
                Icons.card_giftcard_rounded,
                size: 19,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.share_outlined,
                size: 19,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _langBadge(String text, Color color, {bool dotted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _actionIcon(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 19, color: AppColors.textTertiary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
        ),
      ],
    );
  }
}
