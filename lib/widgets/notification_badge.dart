import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme/app_colors.dart';

/// Wraps [child] with a live red unread-count dot, styled the same as the
/// Message tab's badge in main_shell.dart. Wrap just the icon glyph itself
/// (not a whole IconButton, whose invisible tap-target padding would push
/// the badge noticeably away from the visible icon) — see moments_screen.dart's
/// AppBar for the intended usage: `IconButton(icon: NotificationBadge(child: Icon(...)))`.
class NotificationBadge extends StatelessWidget {
  final Widget child;

  const NotificationBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService.streamUnreadCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (count > 0)
              Positioned(
                right: -5,
                top: -3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.badgeRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
