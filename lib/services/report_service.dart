import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/report_model.dart';

/// Writes to `reports/{reportId}`. Client-side read access is intentionally
/// not exposed here — firestore.rules restricts reads to admins, and
/// functions/index.js's onReportCreate keeps `moments/{postId}.reportCount`
/// in sync, so the app never needs to read reports back.
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

    await FirebaseFirestore.instance.collection('reports').add(report.toMap());
  }
}
