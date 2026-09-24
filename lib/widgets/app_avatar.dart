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
  // A real uploaded photo (see StorageService), if any. Mock data uses a
  // single letter for this field instead of a URL, so this is only treated
  // as an image when it actually looks like one.
  final String? imageUrl;

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
    this.imageUrl,
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
      imageUrl: user.avatarUrl,
    );
  }

  bool get _hasImage => imageUrl != null && imageUrl!.startsWith('http');

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
              gradient: _hasImage
                  ? null
                  : LinearGradient(
                      colors: [color, color.withValues(alpha: 0.6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              image: _hasImage
                  ? DecorationImage(
                      image: NetworkImage(imageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
              border: borderWidth > 0
                  ? Border.all(color: borderColor ?? color, width: borderWidth)
                  : null,
            ),
            alignment: Alignment.center,
            child: _hasImage
                ? null
                : Text(
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
                  color: isOnline
                      ? const Color(0xFF3DDC97)
                      : const Color(0xFF6E6E78),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
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

/// A round, white-bordered "sticker" badge showing a country flag —
/// distinct from [AppAvatar]'s own flat `showFlag`/`flag` (a bare emoji
/// character, no background) — this is the more prominent pin-style badge
/// used on a full profile screen's avatar (see connect/
/// partner_profile_screen.dart and me/me_screen.dart), extracted here so
/// both share one definition instead of drifting apart.
class CountryFlagBadge extends StatelessWidget {
  final String flag;
  final double size;

  const CountryFlagBadge({super.key, required this.flag, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4),
        ],
      ),
      child: Center(
        child: Text(flag, style: TextStyle(fontSize: size * 0.54)),
      ),
    );
  }
}
