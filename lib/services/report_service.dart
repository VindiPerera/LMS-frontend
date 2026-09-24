import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/report_model.dart';

/// Writes to `reports/{reportId}`. Client-side read access is intentionally
/// not exposed here — firestore.rules restricts reads to admins.
///
/// `moments/{postId}.reportCount` is bumped client-side alongside the
/// report itself (this project doesn't deploy Cloud Functions — no Blaze
/// plan — so there's no onReportCreate to do it server-side). Nothing in
/// the UI currently displays this count; it's kept accurate anyway for
/// if/when an admin view or auto-hide-after-N-reports feature reads it.
class ReportService {
  static Future<void> reportPost({
    required String postId,
    required ReportReason reason,
    String? details,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || postId.isEmpty) {
      throw StateError('You must be signed in to report a post.');
    }

    final report = ReportModel(
      reporterId: uid,
      postId: postId,
      reason: reason.storageValue,
      details: details,
    );

    final batch = FirebaseFirestore.instance.batch();
    batch.set(FirebaseFirestore.instance.collection('reports').doc(), report.toMap());
    batch.update(FirebaseFirestore.instance.collection('moments').doc(postId), {
      'reportCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Reports a person directly rather than a specific post — the voice
  /// room's "Report" action (room_profile_sheet.dart), available to any
  /// participant against any other participant (see _buildMoreMenu's own
  /// doc comment — this is deliberately NOT limited to a host/moderator,
  /// unlike Mute/Kick Out). No counter to bump here (unlike [reportPost]'s
  /// moments/{postId}.reportCount) — there's no per-user document in this
  /// app to keep one on; the admin panel computes a live count instead
  /// (FirestoreReportService::countForUser, hello-backend).
  static Future<void> reportUser({
    required String reportedUserId,
    String? roomId,
    required UserReportReason reason,
    String? details,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || reportedUserId.isEmpty) {
      throw StateError('You must be signed in to report someone.');
    }

    final report = ReportModel(
      reporterId: uid,
      reportedUserId: reportedUserId,
      roomId: roomId,
      reason: reason.storageValue,
      details: details,
    );

    await FirebaseFirestore.instance.collection('reports').add(report.toMap());
  }
}
