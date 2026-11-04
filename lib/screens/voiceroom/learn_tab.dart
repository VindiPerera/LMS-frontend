import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// The Voiceroom tab's Learn section. Every sub-tab used to render fixed
/// mock content (word packs, a static "AI Talk" card that didn't talk to
/// anything, decorative course banners, and a hardcoded tutor grid) with no
/// backend behind any of it — shown honestly empty instead until there's a
/// real feature here. (Tutor booking from "Me" > My Courses is unrelated
/// and untouched — see course_detail_sheet.dart.)
class LearnTab extends StatefulWidget {
  const LearnTab({super.key});

  @override
  State<LearnTab> createState() => _LearnTabState();
}

class _LearnTabState extends State<LearnTab> {
  static const _subTabs = [
    (label: 'Words', icon: Icons.style_rounded, message: 'Vocabulary word packs are coming soon'),
    (label: 'AI Talk', icon: Icons.smart_toy_rounded, message: 'AI conversation practice is coming soon'),
    (label: 'Classes', icon: Icons.school_rounded, message: 'Live classes are coming soon'),
    (label: 'Courses', icon: Icons.menu_book_rounded, message: 'Structured courses are coming soon'),
  ];
  int _subIndex = 0;

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
                label: Text(_subTabs[i].label),
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
          child: _ComingSoon(
            icon: _subTabs[_subIndex].icon,
            message: _subTabs[_subIndex].message,
          ),
        ),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ComingSoon({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 48),
      children: [
        Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppColors.primaryPurple),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
