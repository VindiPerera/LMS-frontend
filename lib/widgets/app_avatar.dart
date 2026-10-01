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
  // True while this person currently has a live voice-room participant doc
  // (see RoomParticipantService.join/leave and AppUser.activeRoomId) —
  // shows a small purple mic badge in the same bottom-right corner
  // [showOnlineDot]'s plain dot would otherwise occupy, in place of it
  // (being in a voice room already implies being online, so there's
  // nothing the plain dot would add on top of this). Used by
  // chat_list_screen.dart's "in a voice room" indicator.
  final bool inVoiceRoom;

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
    this.inVoiceRoom = false,
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

  // The photo ring's thickness and the small themed-background gap that
  // separates it from the actual photo — both proportional to [size], and
  // both inset WITHIN it (same footprint as a plain [borderWidth], never
  // growing the widget's own bounds), so turning [inVoiceRoom] on never
  // shifts surrounding layout. Kept inside the photo circle specifically so
  // the mic badge, anchored just outside that same circle, is never
  // touched by it — see build()'s own placement of each.
  double get _ringWidth => size * 0.07;
  double get _ringGap => size * 0.035;

  @override
  Widget build(BuildContext context) {
    final color = avatarColorFor(seed);
    final initial = seed.isNotEmpty ? seed.substring(0, 1).toUpperCase() : '?';
    final photoSize = inVoiceRoom ? size - 2 * (_ringWidth + _ringGap) : size;

    Widget photo = Container(
      width: photoSize,
      height: photoSize,
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
                fontSize: photoSize * 0.4,
              ),
            ),
    );

    // A themed-background gap ring between the photo and the gradient ring
    // outside it — the same "small breathing gap" a story-style ring always
    // has, so the ring reads as its own distinct outline rather than
    // bleeding straight into the photo.
    if (inVoiceRoom) {
      photo = Container(
        padding: EdgeInsets.all(_ringGap),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
        child: photo,
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (inVoiceRoom)
            // The "sparkling"/glowing ring itself — several magenta/violet/
            // lilac stops swept around the circle for a shimmering look
            // (rather than one flat border color), plus a soft two-layer
            // glow bleeding outward from it. Kept modest (well under the
            // 14px gap this sits in before whatever's next to it in a Row —
            // see chat_list_screen.dart) since Clip.none below means it
            // isn't clipped to the avatar's own box, so a too-wide glow
            // would bleed into neighboring content.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFFB026FF),
                    Color(0xFF9D4EDD),
                    Color(0xFF7B68F4),
                    Color(0xFFE961FF),
                    Color(0xFFB026FF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFB026FF).withValues(alpha: 0.55), blurRadius: size * 0.16),
                  BoxShadow(color: const Color(0xFF9D4EDD).withValues(alpha: 0.3), blurRadius: size * 0.28),
                ],
              ),
            ),
          Center(child: photo),
          if (inVoiceRoom)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.34,
                height: size * 0.34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF7B68F4),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: Icon(Icons.mic_rounded, color: Colors.white, size: size * 0.19),
              ),
            )
          else if (showOnlineDot)
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
