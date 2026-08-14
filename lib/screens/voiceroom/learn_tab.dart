import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../models/learn_item.dart';
import '../../services/teacher_service.dart';
import '../../theme/app_colors.dart';

import '../../widgets/app_avatar.dart';
import 'english_courses_screen.dart';

class LearnTab extends StatefulWidget {
  const LearnTab({super.key});

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  final _subTabs = const ['Words', 'AI Talk', 'Classes', 'Courses'];
  int _subIndex = 3;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            itemCount: _subTabs.length,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = i == _subIndex;
              return ChoiceChip(
                label: Text(_subTabs[i]),
                selected: selected,
                onSelected: (_) => setState(() => _subIndex = i),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: selected ? Colors.black : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                backgroundColor: AppColors.surfaceLight,
                selectedColor: Colors.white,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _subIndex,
            sizing: StackFit.expand,
            children: [
              const _WordsSubTab(),
              const _AiTalkSubTab(),
              const _ClassesSubTab(),
              const _CoursesSubTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _WordsSubTab extends StatelessWidget {
  const _WordsSubTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      children: [
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (context, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              const labels = [
                'English (American)',
                'English (British)',
                'Korean',
                'Japanese',
              ];
              final selected = i == 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    color: selected ? Colors.black : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 4,
            childAspectRatio: 0.85,
          ),
          itemCount: learnLanguageFlags.length,
          itemBuilder: (context, i) {
            final lang = learnLanguageFlags[i];
            return Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceLight,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    lang['flag']!,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  lang['name']!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Latest Additions',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _WordPackRow(packs: latestWordPacks),
        const SizedBox(height: 22),
        const Text(
          'Recommended for you',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _WordPackRow(packs: recommendedWordPacks),
        const SizedBox(height: 22),
        const Text(
          'Basic words',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _WordPackRow(packs: basicWordPacks),
      ],
    );
  }
}

class _WordPackRow extends StatelessWidget {
  final List<WordPack> packs;
  const _WordPackRow({required this.packs});

  static const _colors = [
    Color(0xFF2E7D5B),
    Color(0xFF2C5A8C),
    Color(0xFFB0783A),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: packs.length,
        separatorBuilder: (context, i) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final pack = packs[i];
          return Container(
            width: 108,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: Icon(
                          pack.locked
                              ? Icons.lock_rounded
                              : Icons.auto_awesome_rounded,
                          color: Colors.white70,
                          size: 26,
                        ),
                      ),
                      if (pack.badge.isNotEmpty)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pack.badge,
                              style: const TextStyle(
                                fontSize: 8.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (pack.locked)
                      const Icon(
                        Icons.lock_rounded,
                        size: 10,
                        color: AppColors.textTertiary,
                      ),
                    if (pack.locked) const SizedBox(width: 3),
                    Text(
                      pack.progress,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AiTalkSubTab extends StatelessWidget {
  const _AiTalkSubTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      children: const [
        _SectionCard(
          title: 'English Ai',
          subtitle: 'Speak English with AI',
          gradient: [Color(0xFF14225C), Color(0xFF0A1230)],
          heading: "Let's Speak\nEnglish",
        ),
      ],
    );
  }
}

class _ClassesSubTab extends StatelessWidget {
  const _ClassesSubTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 4,
            childAspectRatio: 0.8,
          ),
          itemCount: classCategories.length,
          itemBuilder: (context, i) {
            final cat = classCategories[i];
            return Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cat['color'] as Color,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        cat['icon'] as IconData,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    if ((cat['badge'] as String).isNotEmpty)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.badgeRed,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cat['badge'] as String,
                            style: const TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  cat['name'] as String,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pro Partner',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '15,105',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          '15 minutes of daily practice with a Pro Partner',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 10),
        const _SectionCard(
          title: '',
          subtitle: '',
          gradient: [Color(0xFFE8A23C), Color(0xFFE87A3C)],
          heading: 'English Pro Partner',
          caption:
              'Abundant topics to choose from\nChat freely with native partners',
          ctaLabel: 'Book now',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Speaking',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const Text(
              'More',
              style: TextStyle(
                color: AppColors.primaryPurple,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.primaryPurple,
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Free Mode: unlimited languages and language partners',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: speakingTutors.length,
          itemBuilder: (context, i) => _TutorCard(tutor: speakingTutors[i]),
        ),
      ],
    );
  }
}

class _TutorCard extends StatelessWidget {
  final Tutor tutor;
  const _TutorCard({required this.tutor});

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
          Row(
            children: [
              AppAvatar(
                seed: tutor.name,
                size: 40,
                showFlag: true,
                flag: tutor.flag,
              ),
              const Spacer(),
              const Icon(
                Icons.volume_up_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
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
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
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
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => TeacherService.bookTutor(context, teacher: tutorToAppUser(tutor)),
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

class _CoursesSubTab extends StatelessWidget {
  const _CoursesSubTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
      children: [
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: learnCourseCards.length,
            separatorBuilder: (context, i) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _CourseCoverCard(card: learnCourseCards[i]),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionCard(
          title: 'English Ai',
          subtitle: 'Speak English with AI',
          gradient: [Color(0xFF14225C), Color(0xFF0A1230)],
          heading: "Let's Speak\nEnglish",
        ),
        const SizedBox(height: 20),
        const Text(
          'Speaking',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const _SectionCard(
          title: 'Personalized Live Class',
          subtitle: '',
          gradient: [Color(0xFFD9704A), Color(0xFFB84E30)],
          heading: '1-on-1 English\nLiveClass',
          caption: 'Learn with Structured Courses',
          ctaLabel: '🔥 Buy Now!',
        ),
        const SizedBox(height: 20),
        const Text(
          'English Pro Partner',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const _SectionCard(
          title: 'English Pro Partner',
          subtitle: '',
          gradient: [Color(0xFFE8A23C), Color(0xFFE87A3C)],
          heading: 'English Pro Partner',
          caption:
              'Abundant topics to choose from\nChat freely with native partners',
          ctaLabel: 'Book now',
        ),
      ],
    );
  }
}

class _CourseCoverCard extends StatelessWidget {
  final LearnCard card;
  const _CourseCoverCard({required this.card});

  static const _gradients = {
    'course_a': [Color(0xFF6C3FBF), Color(0xFF3A1E80)],
    'course_b': [Color(0xFF8A3FBF), Color(0xFF4A1E80)],
    'course_c': [Color(0xFF3F8ABF), Color(0xFF1E4A80)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[card.coverSeed] ?? _gradients['course_a']!;
    return GestureDetector(
      onTap: () {
        if (card.title == 'HelloEnglish') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EnglishCoursesScreen()),
          );
        }
      },
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(16),
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
            if (card.badge.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  card.badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const Spacer(),
            Text(
              card.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final String heading;
  final String caption;
  final String ctaLabel;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.heading,
    this.caption = '',
    this.ctaLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12.5,
            ),
          ),
        ],
        if (title.isNotEmpty || subtitle.isNotEmpty) const SizedBox(height: 10),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 130),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
                heading,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
              if (ctaLabel.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    ctaLabel,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
