import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The small gold "VIP" pill shown beside a VIP member's name on their
/// profile. Callers only render it when `AppUser.isVip` is true.
class VipBadge extends StatelessWidget {
  final double fontSize;
  const VipBadge({super.key, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.7, vertical: fontSize * 0.25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFD25A), AppColors.vipGold]),
        borderRadius: BorderRadius.circular(fontSize * 0.8),
      ),
      child: Text(
        'VIP',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: AppColors.vipCardText,
          height: 1.2,
        ),
      ),
    );
  }
}
