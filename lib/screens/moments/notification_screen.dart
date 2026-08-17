import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/moment.dart';
import '../../models/notification_model.dart';
import '../../services/moment_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import 'post_detail_screen.dart';

/// Notification feed: `notifications/{uid}/items` ordered newest first.
/// Unread rows get a subtle highlight; tapping one marks it read and opens
/// the relevant post.
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: NotificationService.markAllAsRead,
            child: const Text('Mark all as read', style: TextStyle(color: AppColors.primaryPurple, fontSize: 13)),
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: NotificationService.streamNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.textTertiary),
                    SizedBox(height: 12),
                    Text(
                      "You're all caught up",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => _NotificationTile(notification: items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  Future<void> _open(BuildContext context) async {
    NotificationService.markAsRead(notification.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: notification.postId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      child: Container(
        color: notification.isRead ? Colors.transparent : AppColors.primaryPurple.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AppAvatar(seed: notification.actorName, size: 42, imageUrl: notification.actorAvatar),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.3),
                      children: [
                        TextSpan(
                          text: notification.actorName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' ${notification.type.verb}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(notification.timeAgo, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FutureBuilder<Moment?>(
              future: MomentService.fetchMoment(notification.postId),
              builder: (context, snapshot) {
                final thumbUrl = snapshot.data?.imageUrls.isNotEmpty == true
                    ? snapshot.data!.imageUrls.first
                    : snapshot.data?.videoThumbnailUrl;
                if (thumbUrl == null) return const SizedBox.shrink();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(imageUrl: thumbUrl, width: 44, height: 44, fit: BoxFit.cover),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
