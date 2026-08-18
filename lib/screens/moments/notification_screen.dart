import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/moment.dart';
import '../../models/notification_model.dart';
import '../../services/moment_service.dart';
import '../../services/notification_service.dart';
import '../../services/voice_room_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_avatar.dart';
import '../friends/friend_profile_screen.dart';
import '../voiceroom/voice_room_detail_screen.dart';
import 'post_detail_screen.dart';

/// Notification feed: `notifications/{uid}/items` ordered newest first.
/// Unread rows get a subtle highlight; tapping one marks it read and opens
/// whatever the notification is about — a post, a voice room, or a
/// person's profile, depending on `type`.
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

    switch (notification.type) {
      case NotificationType.friendRequest:
      case NotificationType.friendAccept:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FriendProfileScreen(friendId: notification.actorId, source: 'notification'),
          ),
        );
        return;

      case NotificationType.voiceroom:
        final room = await VoiceRoomService.fetchRoom(notification.postId);
        if (!context.mounted) return;
        if (room == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This Voice Room has ended.')),
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VoiceRoomDetailScreen(room: room)),
        );
        return;

      case NotificationType.like:
      case NotificationType.comment:
      case NotificationType.reshare:
      case NotificationType.mention:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: notification.postId)),
        );
    }
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
            _buildTrailing(),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailing() {
    switch (notification.type) {
      case NotificationType.like:
      case NotificationType.comment:
      case NotificationType.reshare:
      case NotificationType.mention:
        return FutureBuilder<Moment?>(
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
        );

      case NotificationType.voiceroom:
        return Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mic_rounded, color: AppColors.primaryPurple, size: 16),
        );

      case NotificationType.friendRequest:
      case NotificationType.friendAccept:
        return const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary);
    }
  }
}
