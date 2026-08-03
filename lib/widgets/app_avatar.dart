import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../models/user.dart';

/// Circular initials-based avatar so the UI never depends on network images.
class AppAvatar extends StatelessWidget {
  final String seed;
  final double size;
  final bool showOnlineDot;
  final bool isOnline;
  final bool showFlag;
  final String? flag;
  final double borderWidth;
  final Color? borderColor;

  const AppAvatar({
    super.key,
    required this.seed,
    this.size = 48,
    this.showOnlineDot = false,
    this.isOnline = false,
    this.showFlag = false,
    this.flag,
    this.borderWidth = 0,
    this.borderColor,
  });

  factory AppAvatar.forUser(
    AppUser user, {
    double size = 48,
    bool showOnlineDot = false,
    bool showFlag = false,
  }) {
    return AppAvatar(
      seed: user.name,
      size: size,
      showOnlineDot: showOnlineDot,
      isOnline: user.isOnline,
      showFlag: showFlag,
      flag: user.countryFlag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = avatarColorFor(seed);
    final initial = seed.isNotEmpty ? seed.substring(0, 1).toUpperCase() : '?';

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: borderWidth > 0
                  ? Border.all(color: borderColor ?? color, width: borderWidth)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            ),
          ),
          if (showOnlineDot)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFF3DDC97) : const Color(0xFF6E6E78),
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
              ),
            ),
          if (showFlag && flag != null)
            Positioned(
              left: -2,
              bottom: -2,
              child: Text(flag!, style: TextStyle(fontSize: size * 0.26)),
            ),
        ],
      ),
    );
  }
}
