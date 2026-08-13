import 'package:flutter/material.dart';
import '../../data/mock_data.dart' as mock;
import '../../models/learn_item.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';

/// Bottom sheet shown when tapping Teachers / LiveClass / Idioms /
/// Flashcards on the Profile tab's Language Courses grid (see
/// me_screen.dart's _CoursesGrid). Slides up from the bottom, matching
/// AddContactScreen.show()'s modal style. Content is tailored per course —
/// reusing the same mock data/card styles already used elsewhere
/// (learn_tab.dart's tutor cards and word packs, english_courses_screen.dart's
/// gradient banners) — since none of these course areas has a real backend
/// yet; actions are placeholders (a SnackBar), same as "Book tutor" already
/// is in learn_tab.dart.
class CourseDetailSheet extends StatelessWidget {
  final String courseName;

  const CourseDetailSheet({super.key, required this.courseName});

  static void show(BuildContext context, String courseName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CourseDetailSheet(courseName: courseName),
    );
  }

  static void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label — coming soon!')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            titleSpacing: 20,
            automaticallyImplyLeading: false,
            title: Text(
              courseName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (courseName) {
      case 'Teachers':
        return _TeachersBody(
          onBook: (name) => _comingSoon(context, name),
        );
      case 'LiveClass':
        return _LiveClassBody(
          onBuy: (title) => _comingSoon(context, title),
        );
      case 'Idioms':
        return _PackListBody(
          subtitle: 'Learn everyday idioms and expressions',
          packs: const [
            WordPack(title: 'Everyday Idioms', progress: '0/12', badge: 'New'),
            WordPack(title: 'Idioms about Time', progress: '0/10'),
            WordPack(title: 'Animal Idioms', progress: '0/8'),
            WordPack(title: 'Weather Idioms', progress: 'Locked', locked: true),
            WordPack(title: 'Business Idioms', progress: 'Locked', locked: true),
          ],
          onTapPack: (title) => _comingSoon(context, title),
        );
      case 'Flashcards':
        return _PackListBody(
          subtitle: 'Quick flashcard decks to build vocabulary',
          packs: const [
            WordPack(title: 'Travel Words', progress: '0/15', badge: 'New'),
            WordPack(title: 'Food & Dining', progress: '0/12'),
            WordPack(title: 'Numbers', progress: '0/10'),
            WordPack(title: 'Advanced Vocabulary', progress: 'Locked', locked: true),
          ],
          onTapPack: (title) => _comingSoon(context, title),
        );
      default:
        return const Center(
          child: Text(
            'Coming soon',
            style: TextStyle(color: AppColors.textTertiary),
          ),
        );
    }
  }
}

class _TeachersBody extends StatelessWidget {
  final ValueChanged<String> onBook;
  const _TeachersBody({required this.onBook});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.76,
      ),
      itemCount: mock.speakingTutors.length,
      itemBuilder: (context, i) {
        final tutor = mock.speakingTutors[i];
        return _TutorTile(
          tutor: tutor,
          onBook: () => onBook('Book ${tutor.name}'),
        );
      },
    );
  }
}

class _TutorTile extends StatelessWidget {
  final Tutor tutor;
  final VoidCallback onBook;
  const _TutorTile({required this.tutor, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(seed: tutor.name, size: 40, showFlag: true, flag: tutor.flag),
          const SizedBox(height: 8),
          Text(
            tutor.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tutor.languages,
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              tutor.bio,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: tutor.isPro
                    ? const Color(0xFFE8A23C)
                    : AppColors.textSecondary,
                fontWeight: tutor.isPro ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onBook,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFE9D9),
                foregroundColor: const Color(0xFFD9722E),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text(
                'Book tutor',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveClassBody extends StatelessWidget {
  final ValueChanged<String> onBuy;
  const _LiveClassBody({required this.onBuy});

  static const _classes = [
    (
      title: '1-on-1 English LiveClass',
      caption: 'Learn with structured courses',
      gradient: [Color(0xFFD9704A), Color(0xFFB84E30)],
    ),
    (
      title: '1-on-1 Korean LiveClass',
      caption: 'Structured lessons with certified tutors',
      gradient: [Color(0xFF2CB5C0), Color(0xFF1B8A94)],
    ),
    (
      title: '1-on-1 Japanese LiveClass',
      caption: 'Learn at your own pace, one on one',
      gradient: [Color(0xFFFF9A3D), Color(0xFFFF6A3D)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        const Text(
          'Structured, 1-on-1 live classes with a real tutor',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 13.5),
        ),
        const SizedBox(height: 18),
        for (final c in _classes) ...[
          _LiveClassCard(
            title: c.title,
            caption: c.caption,
            gradient: c.gradient,
            onBuy: () => onBuy(c.title),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _LiveClassCard extends StatelessWidget {
  final String title;
  final String caption;
  final List<Color> gradient;
  final VoidCallback onBuy;

  const _LiveClassCard({
    required this.title,
    required this.caption,
    required this.gradient,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18.5,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onBuy,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Buy Now!',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.play_arrow_rounded, size: 14, color: Colors.black),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackListBody extends StatelessWidget {
  final String subtitle;
  final List<WordPack> packs;
  final ValueChanged<String> onTapPack;

  const _PackListBody({
    required this.subtitle,
    required this.packs,
    required this.onTapPack,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: packs.length + 1,
      separatorBuilder: (context, i) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13.5,
              ),
            ),
          );
        }
        final pack = packs[i - 1];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTapPack(pack.title),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: pack.locked
                        ? AppColors.surfaceLight
                        : AppColors.primaryPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    pack.locked ? Icons.lock_rounded : Icons.style_rounded,
                    color: pack.locked
                        ? AppColors.textTertiary
                        : AppColors.primaryPurple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              pack.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                          ),
                          if (pack.badge.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                pack.badge,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pack.progress,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
      },
    );
  }
}
