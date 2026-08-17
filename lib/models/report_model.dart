import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportReason {
  spam,
  inappropriate,
  harassment,
  other;

  String get storageValue => name;

  String get label {
    switch (this) {
      case ReportReason.spam:
        return 'Spam';
      case ReportReason.inappropriate:
        return 'Inappropriate content';
      case ReportReason.harassment:
        return 'Harassment or bullying';
      case ReportReason.other:
        return 'Other';
    }
  }
}

/// A single `reports/{reportId}` document. Write-only from the client —
/// firestore.rules restricts reads to admins.
class ReportModel {
  final String reporterId;
  final String postId;
  final ReportReason reason;
  final String? details;

  const ReportModel({
    required this.reporterId,
    required this.postId,
    required this.reason,
    this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'reporterId': reporterId,
      'postId': postId,
      'reason': reason.storageValue,
      if (details != null && details!.trim().isNotEmpty)
        'details': details!.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
