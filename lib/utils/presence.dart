import 'package:cloud_firestore/cloud_firestore.dart';

/// How long a user still counts as online after their last heartbeat
/// (see AuthService.setOnlineStatus, written on login/logout, every app
/// foreground/background transition, and periodically while foregrounded).
/// A few heartbeats' worth of slack so one missed beat (brief network blip)
/// doesn't flicker the dot, but an abrupt kill/crash — which skips the
/// normal "paused" offline write entirely — self-corrects within this
/// window instead of leaving `isOnline: true` stuck forever.
const presenceStaleAfter = Duration(seconds: 90);

/// The source of truth for whether a user actually counts as online:
/// combines the raw `isOnline` flag with `lastSeenAt` staleness. Firestore
/// has no built-in disconnect detection (unlike Realtime Database's
/// onDisconnect()), so `isOnline` alone can be stale; every place that
/// shows a green "online" dot should go through this rather than reading
/// `isOnline` directly.
bool isActuallyOnline(bool rawIsOnline, Timestamp? lastSeenAt) {
  if (!rawIsOnline || lastSeenAt == null) return false;
  return DateTime.now().difference(lastSeenAt.toDate()) < presenceStaleAfter;
}
