import 'package:flutter/material.dart';

import '../models/report_model.dart';
import '../services/report_service.dart';
import '../theme/app_colors.dart';

/// Shows the report-reason bottom sheet and submits to ReportService.
/// Returns true once a report was actually filed, so the caller
/// (moment_card.dart) knows to hide the post locally and show the "Thanks
/// for your report" snackbar.
Future<bool> showReportSheet(BuildContext context, {required String postId}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReportSheet(postId: postId),
  );
  return result ?? false;
}

class ReportSheet extends StatefulWidget {
  final String postId;

  const ReportSheet({super.key, required this.postId});

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _detailsController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ReportService.reportPost(
        postId: widget.postId,
        reason: _reason!,
        details: _reason == ReportReason.other ? _detailsController.text : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit your report. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Report this moment',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                "Help us understand what's wrong with this post.",
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              ...ReportReason.values.map(
                (reason) => RadioListTile<ReportReason>(
                  value: reason,
                  groupValue: _reason,
                  onChanged: (value) => setState(() => _reason = value),
                  title: Text(reason.label, style: const TextStyle(fontSize: 14)),
                  activeColor: AppColors.primaryPurple,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              if (_reason == ReportReason.other)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: TextField(
                    controller: _detailsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Tell us more (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.badgeRed, fontSize: 12)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _reason == null || _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Submit report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
