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
      reason: reason,
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
}
