import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Live video streaming is a separate feature from Voice Rooms (see
/// voice_room_service.dart) with no backend of its own yet — this tab used
/// to render `mockLiveStreams` (lib/data/mock_data.dart), fake cards with
/// made-up hosts/viewer counts that never reflected anything real. Shown
/// honestly empty until a real Live backend exists, rather than data that
/// looks live but isn't.
class LiveTab extends StatelessWidget {
  const LiveTab({super.key});

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
              child: const Icon(
                Icons.live_tv_rounded,
                size: 38,
                color: AppColors.primaryPurple,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Live streaming is coming soon',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                "In the meantime, head over to Voice to join or start a live voice room.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
