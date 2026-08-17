import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/moment.dart';
import '../screens/friends/friend_profile_screen.dart';
import '../screens/moments/image_viewer_screen.dart';
import '../screens/moments/video_player_screen.dart';
import '../services/moment_service.dart';
import '../theme/app_colors.dart';
import 'app_avatar.dart';
import 'post_image_grid.dart';

/// Read-only preview of the original post inside a reshare. No like/
/// comment/reshare actions of its own — tapping media still opens the
/// full-screen viewer/player, and tapping the author still opens their
/// profile, since those are just navigation, not engagement with this copy
/// of the post.
class EmbeddedPostCard extends StatelessWidget {
  final String originalPostId;

  const EmbeddedPostCard({super.key, required this.originalPostId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Moment?>(
      future: MomentService.fetchMoment(originalPostId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }

        final original = snapshot.data;
        if (original == null) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.link_off_rounded, size: 18, color: AppColors.textTertiary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Original post has been removed',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return _shell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    if (original.user.id.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FriendProfileScreen(
                          friendId: original.user.id,
                          source: 'moment',
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      AppAvatar.forUser(original.user, size: 30, showFlag: true),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              original.user.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            Text(
                              original.timeAgo,
                              style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (original.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      original.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                if (original.imageUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: PostImageGrid(
                        postId: original.id,
                        imageUrls: original.imageUrls,
                        onTapImage: (index) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ImageViewerScreen(
                              postId: original.id,
                              imageUrls: original.imageUrls,
                              initialIndex: index,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (original.mediaType == MomentMediaType.video && original.videoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(videoUrl: original.videoUrl!),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (original.videoThumbnailUrl != null)
                                CachedNetworkImage(
                                  imageUrl: original.videoThumbnailUrl!,
                                  fit: BoxFit.cover,
                                )
                              else
                                Container(color: Colors.black),
                              Container(color: Colors.black.withValues(alpha: 0.25)),
                              const Center(
                                child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 44),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}
