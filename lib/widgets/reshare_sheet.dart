import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/moment.dart';
import '../services/moment_service.dart';
import '../theme/app_colors.dart';
import 'embedded_post_card.dart';
import 'visibility_selector.dart';

/// Shows the reshare bottom sheet for [original] and, on confirm, creates
/// the new `isReshare: true` moment. `reshareCount` on [original] is never
/// touched here — functions/index.js's onReshare owns it. Returns true once
/// the reshare was actually created.
Future<bool> showReshareSheet(BuildContext context, {required Moment original}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReshareSheet(original: original),
  );
  return result ?? false;
}

class ReshareSheet extends StatefulWidget {
  final Moment original;

  const ReshareSheet({super.key, required this.original});

  @override
  State<ReshareSheet> createState() => _ReshareSheetState();
}

class _ReshareSheetState extends State<ReshareSheet> {
  final _captionController = TextEditingController();
  MomentVisibility _visibility = MomentVisibility.public;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _reshare() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await MomentService.createMoment(
        text: _captionController.text,
        visibility: _visibility,
        isReshare: true,
        originalPostId: widget.original.id,
      );
      if (!mounted) return;
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
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
              const Text('Reshare moment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(
                controller: _captionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add a caption (optional)',
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  border: InputBorder.none,
                ),
              ),
              EmbeddedPostCard(originalPostId: widget.original.id),
              const SizedBox(height: 14),
              const Text(
                'Who can see your reshare?',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              VisibilitySelector(value: _visibility, onChanged: (v) => setState(() => _visibility = v)),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: AppColors.badgeRed, fontSize: 12)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _reshare,
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
                      : const Text('Reshare'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
