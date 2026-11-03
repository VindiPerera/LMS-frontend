import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Bottom sheet shown when tapping a Language Courses tile on the Profile
/// tab (see me_screen.dart's _CoursesGrid). Previously had a different mock
/// body per course (a hardcoded tutor grid, static "Buy Now!" banners, word
/// packs) with no real backend behind any of it — simplified to one honest
/// "coming soon" state, consistent with voiceroom/learn_tab.dart (which had
/// the exact same kind of placeholder content and was cleaned up the same
/// way).
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: FractionallySizedBox(
        heightFactor: 0.6,
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
                icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(top: 24),
            children: [
              Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu_book_rounded, size: 32, color: AppColors.primaryPurple),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$courseName is coming soon',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
