import 'package:flutter/material.dart';

/// Color palette matching FaceTalk's light UI with purple accents.
class AppColors {
  AppColors._();

  static const Color primaryPurple = Color(0xFF7B68F4);
  static const Color primaryPurpleDark = Color(0xFF6C5CE7);
  static const Color background = Color(0xFFF7F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF0F0F4);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE7E7ED);

  static const Color textPrimary = Color(0xFF1A1A1F);
  static const Color textSecondary = Color(0xFF6E6E78);
  static const Color textTertiary = Color(0xFF9B9BA5);

  static const Color vipGold = Color(0xFFE8A23C);
  static const Color vipCardBg = Color(0xFFF4EFDD);
  static const Color vipCardText = Color(0xFF7A5B1E);

  static const Color streakOrange = Color(0xFFFF7A45);
  static const Color online = Color(0xFF2ECC71);
  static const Color badgeRed = Color(0xFFFF4757);
  static const Color badgePink = Color(0xFFFF4D8D);

  static const List<Color> flagGreen = [Color(0xFF2ECC71), Color(0xFF27AE60)];

  static const Color correctionBlue = Color(0xFF4FA8FF);
  static const Color perfectGreen = Color(0xFF2ECC71);

  static const Gradient voiceroomHeader = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF3F1FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient vipBannerGradient = LinearGradient(
    colors: [Color(0xFFD9D4FB), Color(0xFFEDEBFD)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
