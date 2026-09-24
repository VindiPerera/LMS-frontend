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

/// Reasons for reporting a PERSON directly (room_profile_sheet.dart's
/// "Report" action on a voice room participant) — deliberately a separate
/// enum from [ReportReason] rather than reusing/extending it, so Moments'
/// post-reporting taxonomy (report_sheet.dart/moment_card.dart/
/// comment_sheet.dart) is completely unaffected by this one changing.
/// firestore.rules' `reports/{reportId}` create rule validates each
/// taxonomy against its own allow-list, keyed off which of postId/
/// reportedUserId is set — keep both in sync if either ever changes.
enum UserReportReason {
  languagesMismatch,
  fraud,
  sexualContent,
  abusiveLanguage,
  religiousPoliticalContent,
  other;

  String get storageValue => name;

  String get label {
    switch (this) {
      case UserReportReason.languagesMismatch:
        return 'Languages used and set do not match';
      case UserReportReason.fraud:
        return 'Attempted/committed fraud';
      case UserReportReason.sexualContent:
        return 'Sent sexual content';
      case UserReportReason.abusiveLanguage:
        return 'Used abusive language';
      case UserReportReason.religiousPoliticalContent:
        return 'Sent religious/political content';
      case UserReportReason.other:
        return 'Other';
    }
  }
}

/// A single `reports/{reportId}` document. Write-only from the client —
/// firestore.rules restricts reads to admins. Exactly one of [postId] /
/// [reportedUserId] is set depending on what's being reported — a Moments
/// post (report_sheet.dart, from the feed) or a person directly
/// (room_profile_sheet.dart's "Report" action on a voice room participant).
/// firestore.rules' `reports/{reportId}` create rule only ever checks
/// `reporterId`/`reason`, so neither field needs to be present for a write
/// to be allowed — this is purely about giving an admin reviewer enough
/// context to know what was reported.
///
/// [reason] is a plain storage-value string rather than [ReportReason]
/// directly — [ReportService.reportPost]/[ReportService.reportUser] each
/// pass their own enum's `.storageValue` ([ReportReason] vs
/// [UserReportReason]), so this model stays agnostic to which taxonomy a
/// given report used.
class ReportModel {
  final String reporterId;
  final String? postId;
  final String? reportedUserId;
  // Which room a user-report happened in, if any — extra context for an
  // admin reviewer, not used for access control.
  final String? roomId;
  final String reason;
  final String? details;

  const ReportModel({
    required this.reporterId,
    this.postId,
    this.reportedUserId,
    this.roomId,
    required this.reason,
    this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'reporterId': reporterId,
      if (postId != null) 'postId': postId,
      if (reportedUserId != null) 'reportedUserId': reportedUserId,
      if (roomId != null) 'roomId': roomId,
      'reason': reason,
      if (details != null && details!.trim().isNotEmpty)
        'details': details!.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
