import 'package:flutter/material.dart';

import '../models/moment.dart';
import '../theme/app_colors.dart';

// MomentVisibility.friends' storage value stays 'friends' (existing posts
// are already stored that way — see MomentService._audienceFor's doc
// comment), but the app has no "friends" relationship anymore, just Follow —
// so this reads as "Followers" here, the only place that enum value is ever
// shown to a user.
const List<(MomentVisibility, IconData, String)> _kVisibilityOptions = [
  (MomentVisibility.public, Icons.public_rounded, 'Public'),
  (MomentVisibility.friends, Icons.people_rounded, 'Followers'),
  (MomentVisibility.onlyMe, Icons.lock_outline_rounded, 'Only me'),
];

/// Segmented Public / Followers / Only me picker, shared by
/// create_moment_screen.dart (new post visibility) and reshare_sheet.dart
/// (the reshare's own visibility).
class VisibilitySelector extends StatelessWidget {
  final MomentVisibility value;
  final ValueChanged<MomentVisibility> onChanged;

  const VisibilitySelector({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _kVisibilityOptions.map((option) {
        final (visibility, icon, label) = option;
        final selected = value == visibility;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(visibility),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryPurple.withValues(alpha: 0.12)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.primaryPurple : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: selected ? AppColors.primaryPurple : AppColors.textTertiary),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.primaryPurple : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
