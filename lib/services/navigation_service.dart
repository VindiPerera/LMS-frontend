import 'package:flutter/material.dart';

import '../screens/moments/post_detail_screen.dart';

/// A global [NavigatorState] key, assigned to `MaterialApp.navigatorKey` in
/// main.dart. Needed because push notifications can be tapped while there's
/// no relevant `BuildContext` at hand — the notification tap handlers live
/// in push_notification_service.dart, well outside the widget tree.
class NavigationService {
  NavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Deep-links to a single moment, e.g. from a tapped push notification or
  /// a notification_screen.dart row.
  static void openPost(String postId) {
    if (postId.isEmpty) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
    );
  }
}
