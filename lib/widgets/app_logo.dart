import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// FaceTalk brand mark: a rounded gradient tile with a speech-bubble glyph.
/// Used on the splash screen and auth screens so the branding stays
/// consistent without depending on an external image asset.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showLabel;

  const AppLogo({super.key, this.size = 88, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            gradient: const LinearGradient(
              colors: [AppColors.primaryPurple, AppColors.primaryPurpleDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryPurple.withValues(alpha: 0.35),
                blurRadius: size * 0.25,
                offset: Offset(0, size * 0.08),
              ),
            ],
          ),
          child: Icon(
            Icons.forum_rounded,
            color: Colors.white,
            size: size * 0.52,
          ),
        ),
        if (showLabel) ...[
          SizedBox(height: size * 0.22),
          Text(
            'FaceTalk',
            style: TextStyle(
              fontSize: size * 0.3,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}
