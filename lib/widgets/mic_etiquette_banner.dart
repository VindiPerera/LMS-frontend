import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A permanent community-guideline reminder shown at the top of the Voice
/// tab's room feed — nudging users toward good mic etiquette (mute when
/// you're not speaking) before they ever join a room, rather than only
/// after (see voiceroom_screen.dart's per-room "Please mute your mic"
/// notice on a host's own card, and voice_room_detail_screen.dart's
/// one-off snackbar right after creating a room).
///
/// This replaces what used to be a hardcoded "FIFA World Cup VoiceRoom"
/// promo banner — decorative placeholder copy that meant nothing outside
/// one specific event — with a notice that's actually useful in every
/// deployment of this app.
///
/// Styled as a soft, low-alarm reminder (no heading, no border) and shown
/// unconditionally, with no dismiss control: this is a standing rule, not a
/// one-time tip, so it stays on screen for every visit to the tab rather
/// than being dismissable and then gone for good.
class MicEtiquetteBanner extends StatelessWidget {
  const MicEtiquetteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.badgeRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Please mute your mic when you're not speaking",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
          Text(
            "it keeps rooms clear for everyone",
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Mute your mic',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.badgeRed),
              ),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.badgeRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_off_rounded, size: 15, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
