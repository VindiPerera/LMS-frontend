import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class EnglishCoursesScreen extends StatelessWidget {
  const EnglishCoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('English Courses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          _HotPickBanner(),
          const SizedBox(height: 22),
          const Text('AI Talk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const _CourseSection(
            title: 'English Ai',
            subtitle: 'Speak English with AI',
            gradient: [Color(0xFF14225C), Color(0xFF0A1230)],
            heading: "Let's Speak\nEnglish",
          ),
          const SizedBox(height: 22),
          const Text('Speaking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const _CourseSection(
            title: 'Personalized Live Class',
            subtitle: '',
            gradient: [Color(0xFFD9704A), Color(0xFFB84E30)],
            heading: '1-on-1 English\nLiveClass',
            caption: 'Learn with Structured Courses',
            ctaLabel: '🔥 Buy Now!',
          ),
          const SizedBox(height: 22),
          const Text('English Pro Partner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const _CourseSection(
            title: 'English Pro Partner',
            subtitle: '',
            gradient: [Color(0xFFE8A23C), Color(0xFFE87A3C)],
            heading: 'English Pro Partner',
            caption: 'Abundant topics to choose from\nChat freely with native partners',
            ctaLabel: 'Book now',
          ),
        ],
      ),
    );
  }
}

class _HotPickBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5B39), Color(0xFFFF8A3D)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -18,
            top: -8,
            child: Transform.rotate(
              angle: -0.35,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFC9E8), borderRadius: BorderRadius.circular(6)),
                child: const Text('Hot\nPick', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB4008C), fontSize: 10, fontWeight: FontWeight.w800, height: 1.1)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                '1-on-1 English LiveClass',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: Icon(Icons.emoji_emotions_rounded, color: Colors.white38, size: 56),
          ),
        ],
      ),
    );
  }
}

class _CourseSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final String heading;
  final String caption;
  final String ctaLabel;

  const _CourseSection({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.heading,
    this.caption = '',
    this.ctaLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppColors.textTertiary, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 150),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  heading,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(caption, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
                if (ctaLabel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ctaLabel, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.black),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
