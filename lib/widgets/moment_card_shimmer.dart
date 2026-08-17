import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Skeleton placeholder shown (x3) while the feed's first page loads.
class MomentCardShimmer extends StatelessWidget {
  const MomentCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceLight,
      highlightColor: AppColors.surface,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Block(width: 44, height: 44, radius: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _Block(width: 120, height: 12, radius: 6),
                      SizedBox(height: 6),
                      _Block(width: 80, height: 10, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _Block(width: double.infinity, height: 12, radius: 6),
            const SizedBox(height: 6),
            const _Block(width: 220, height: 12, radius: 6),
            const SizedBox(height: 12),
            const _Block(width: double.infinity, height: 160, radius: 12),
            const SizedBox(height: 12),
            Row(
              children: const [
                _Block(width: 50, height: 12, radius: 6),
                SizedBox(width: 20),
                _Block(width: 50, height: 12, radius: 6),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _Block({required this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
