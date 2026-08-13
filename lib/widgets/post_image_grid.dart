import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Renders a post's `imageUrls` in the Facebook-style 1/2/3/4+ layout and
/// hands taps back to the caller (moment_card.dart pushes
/// image_viewer_screen.dart with the tapped index). Not a ListView — the
/// count is capped at a handful of fixed cells, not an open-ended list.
class PostImageGrid extends StatelessWidget {
  final String postId;
  final List<String> imageUrls;
  final void Function(int index) onTapImage;

  const PostImageGrid({
    super.key,
    required this.postId,
    required this.imageUrls,
    required this.onTapImage,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();

    switch (imageUrls.length) {
      case 1:
        return AspectRatio(
          aspectRatio: 4 / 3,
          child: _Cell(url: imageUrls[0], heroTag: _heroTag(0), onTap: () => onTapImage(0)),
        );
      case 2:
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Row(
            children: [
              Expanded(
                child: _Cell(url: imageUrls[0], heroTag: _heroTag(0), onTap: () => onTapImage(0)),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _Cell(url: imageUrls[1], heroTag: _heroTag(1), onTap: () => onTapImage(1)),
              ),
            ],
          ),
        );
      case 3:
        return AspectRatio(
          aspectRatio: 4 / 3,
          child: Column(
            children: [
              Expanded(
                child: _Cell(url: imageUrls[0], heroTag: _heroTag(0), onTap: () => onTapImage(0)),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _Cell(url: imageUrls[1], heroTag: _heroTag(1), onTap: () => onTapImage(1)),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _Cell(url: imageUrls[2], heroTag: _heroTag(2), onTap: () => onTapImage(2)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        final extra = imageUrls.length - 4;
        return AspectRatio(
          aspectRatio: 1,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _Cell(url: imageUrls[0], heroTag: _heroTag(0), onTap: () => onTapImage(0)),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _Cell(url: imageUrls[1], heroTag: _heroTag(1), onTap: () => onTapImage(1)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _Cell(url: imageUrls[2], heroTag: _heroTag(2), onTap: () => onTapImage(2)),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _Cell(
                        url: imageUrls[3],
                        heroTag: _heroTag(3),
                        onTap: () => onTapImage(3),
                        overlayLabel: extra > 0 ? '+$extra more' : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  String _heroTag(int index) => 'post_image_${postId}_$index';
}

class _Cell extends StatelessWidget {
  final String url;
  final String heroTag;
  final VoidCallback onTap;
  final String? overlayLabel;

  const _Cell({
    required this.url,
    required this.heroTag,
    required this.onTap,
    this.overlayLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: heroTag,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(color: AppColors.surfaceLight),
              errorWidget: (context, _, error) => Container(
                color: AppColors.surfaceLight,
                child: const Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
              ),
            ),
            if (overlayLabel != null)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                alignment: Alignment.center,
                child: Text(
                  overlayLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
