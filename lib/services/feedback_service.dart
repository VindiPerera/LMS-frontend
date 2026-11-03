import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Writes to `feedback/{feedbackId}` — me_screen.dart's "Help & Feedback".
/// Write-only from the client (firestore.rules restricts reads to admins),
/// same shape as report_service.dart.
class FeedbackService {
  static Future<void> submit(String message) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final clean = message.trim();
    if (uid == null || clean.isEmpty) {
      throw StateError('You must be signed in to send feedback.');
    }

    await FirebaseFirestore.instance.collection('feedback').add({
      'userId': uid,
      'message': clean,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
